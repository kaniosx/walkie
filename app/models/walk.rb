class Walk < ApplicationRecord
  belongs_to :dog
  belongs_to :owner, class_name: "User"
  belongs_to :accepted_by_walker, class_name: "User", optional: true

  # String-backed, mirrors User#role. The DB walks_state_valid CHECK is the
  # binding backstop; this enum is the advisory AR layer + predicates/scopes.
  enum :state, {
    requested: "requested",
    accepted: "accepted",
    in_progress: "in_progress",
    completed: "completed",
    cancelled: "cancelled"
  }

  # "Active" = the walk is occupying a dog right now (not yet finished or
  # cancelled). Used to enforce one active request per dog at creation.
  scope :active, -> { where(state: %w[requested accepted in_progress]) }

  MATCH_RADIUS_KM = 10
  EARTH_RADIUS_KM = 6371.0

  # Radius-aware match: city stays a coarse pre-filter (reuses the existing
  # [state, city] index before the distance check runs), then earth_distance
  # narrows to MATCH_RADIUS_KM. earth_distance/ll_to_earth return meters, so
  # the km constant is scaled up. Filtering only — no distance sort (locked
  # decision, see plan §What We're NOT Doing).
  scope :open_nearby, ->(city:, latitude:, longitude:) {
    requested
      .where(city: city)
      .where.not(latitude: nil, longitude: nil)
      .where(
        "earth_distance(ll_to_earth(latitude, longitude), ll_to_earth(?, ?)) <= ?",
        latitude, longitude, MATCH_RADIUS_KM * 1000
      )
  }

  validates :state, presence: true
  validates :city, presence: true
  validates :latitude, :longitude, presence: true
  validate :owner_matches_dog_owner
  validate :walker_is_not_owner
  validate :owner_has_owner_role
  validate :walker_has_walker_role
  # One active request per dog (a dog is walked once at a time). Create-time
  # only; NOT a PRD Singleness invariant (that's one walker per walk, enforced
  # DB-side on accept), so a model guard is proportionate — no DB constraint.
  validate :no_active_walk_for_dog, on: :create

  # Regular save (not swap_state's update_all), so callbacks fire normally.
  after_create_commit :broadcast_creation

  # --- Transitions ---------------------------------------------------------
  # Each transition is a single atomic compare-and-swap UPDATE: the expected
  # state (and, where relevant, the authorizing walker/owner) live in the
  # WHERE clause, so ordering + authorization + the accept race are all
  # decided by the one write. Returns truthy when this call performed the
  # transition, falsy when it didn't apply (wrong state / not authorized /
  # lost the race). update_all skips validations & callbacks, so updated_at
  # is set explicitly and the DB CHECK constraints remain the consistency
  # backstop. See plan §Critical Implementation Details.

  def accept!(walker)
    # update_all skips AR validations and the DB CHECKs don't cover role or
    # owner != walker, so guard both here. Race-free: role is immutable
    # (User#role_is_immutable) and owner_id is fixed at creation.
    return false unless walker.walker? && walker.id != owner_id

    swap_state(from: "requested", to: "accepted",
               guard: {},
               set: { accepted_by_walker_id: walker.id, accepted_at: Time.current })
  end

  def start!(walker)
    swap_state(from: "accepted", to: "in_progress",
               guard: { accepted_by_walker_id: walker.id },
               set: { started_at: Time.current })
  end

  def complete!(walker)
    swap_state(from: "in_progress", to: "completed",
               guard: { accepted_by_walker_id: walker.id },
               set: { completed_at: Time.current })
  end

  def cancel!(owner)
    swap_state(from: "requested", to: "cancelled",
               guard: { owner_id: owner.id },
               set: { cancelled_at: Time.current })
  end

  private
    def swap_state(from:, to:, guard:, set:)
      attrs = set.merge(state: to, updated_at: Time.current)
      affected = self.class.where(id: id, state: from, **guard).update_all(attrs)
      return false unless affected == 1

      reload
      broadcast_transition(from: from)
      true
    end

    # --- Broadcasting --------------------------------------------------------
    # update_all (above) skips callbacks, so transition broadcasts are called
    # explicitly here rather than via after_update_commit. Every broadcast
    # replaces a whole, always-present container — see plan §Implementation
    # Approach. Broadcasts run synchronously (not the _later/ActiveJob variant):
    # deterministic for tests, negligible cost at this scale.

    def broadcast_creation
      broadcast_open_requests_locality
      broadcast_owner_active_walks
    end

    def broadcast_transition(from:)
      broadcast_owner_active_walks
      broadcast_open_requests_locality if from == "requested"
      broadcast_walker_current_walk if accepted_by_walker_id.present?
    end

    # Per-Walker fan-out: every same-city Walker with a live (unexpired)
    # cached location gets their own broadcast, computed from *their* own
    # position, not this walk's. "Not currently viewing, no cache entry" is
    # the expected common case, not an error — silently skipped. Distance
    # here is a small in-memory Ruby computation (bounded by same-city Walker
    # count), not a new SQL predicate; see plan §Phase 5.
    def broadcast_open_requests_locality
      User.walker.where(city: city).find_each do |walker|
        location = WalkerLocationCache.read(walker)
        next if location.nil?
        next unless distance_km_to(location[:latitude], location[:longitude]) <= MATCH_RADIUS_KM

        walks = self.class.open_nearby(city: city, latitude: location[:latitude], longitude: location[:longitude])
                    .includes(:dog).order(created_at: :asc)
        broadcast_replace_to([ walker, :nearby_open_requests ],
                              target: "open_requests_list", partial: "open_requests/list",
                              locals: { walks: walks, city: city })
        broadcast_replace_to([ walker, :nearby_open_requests ],
                              target: "open_requests_count", partial: "home/open_requests_count",
                              locals: { count: walks.size, city: city })
      end
    end

    # Ruby-side Haversine distance from this walk's own coordinates to an
    # arbitrary point — used only to decide broadcast eligibility per cached
    # Walker location in #broadcast_open_requests_locality above. The
    # DB-side `open_nearby` scope stays the source of truth for actual list
    # filtering/queries.
    def distance_km_to(other_latitude, other_longitude)
      rlat1 = latitude.to_f * Math::PI / 180
      rlat2 = other_latitude.to_f * Math::PI / 180
      dlat = rlat2 - rlat1
      dlng = (other_longitude.to_f - longitude.to_f) * Math::PI / 180

      a = Math.sin(dlat / 2)**2 + Math.cos(rlat1) * Math.cos(rlat2) * Math.sin(dlng / 2)**2
      2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a))
    end

    def broadcast_walker_current_walk
      walk = self.class.where(accepted_by_walker_id: accepted_by_walker_id, state: %w[accepted in_progress])
                 .includes(:dog, :owner).first
      broadcast_replace_to([ accepted_by_walker, :current_walk ],
                            target: "walker_current_walk", partial: "walker_walks/current_walk",
                            locals: { walk: walk })
    end

    def broadcast_owner_active_walks
      walks = owner.owned_walks.active.includes(:dog).order(created_at: :desc)
      broadcast_replace_to([ owner, :active_walks ],
                            target: "owner_active_walks_home", partial: "home/owner_active_walks",
                            locals: { walks: walks })
      broadcast_replace_to([ owner, :active_walks ],
                            target: "owner_active_walks_table", partial: "walks/active_table",
                            locals: { walks: walks })
    end

    # A dog can only be walked once at a time: reject a new request when the
    # dog already has an active (requested/accepted/in_progress) walk. exists?
    # hits the DB, so it counts only persisted walks, never the unsaved record.
    def no_active_walk_for_dog
      return if dog.nil?

      errors.add(:base, "This dog already has an active walk request") if dog.walks.active.exists?
    end

    # owner_id is denormalized (= dog.user_id); reject any AR write that would
    # let the two drift apart.
    def owner_matches_dog_owner
      return if dog.nil? || owner_id.nil?

      errors.add(:owner_id, "must match the dog's owner") if owner_id != dog.user_id
    end

    def walker_is_not_owner
      return if accepted_by_walker_id.nil?

      errors.add(:accepted_by_walker, "cannot be the owner") if accepted_by_walker_id == owner_id
    end

    def owner_has_owner_role
      return if owner.nil?

      errors.add(:owner, "must be an Owner") unless owner.owner?
    end

    def walker_has_walker_role
      return if accepted_by_walker.nil?

      errors.add(:accepted_by_walker, "must be a Walker") unless accepted_by_walker.walker?
    end
end
