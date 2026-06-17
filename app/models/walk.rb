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

  # Open requests a walker in this locality can accept: REQUESTED + exact
  # city + postcode match (PRD coarse locality, §Open Q #6). Backed by the
  # [state, city] index; postcode is a cheap residual filter.
  scope :open_in_locality, ->(city, postcode) { requested.where(city: city, postcode: postcode) }

  validates :state, presence: true
  validates :city, presence: true
  validates :postcode, presence: true
  validate :owner_matches_dog_owner
  validate :walker_is_not_owner
  validate :owner_has_owner_role
  validate :walker_has_walker_role
  # One active request per dog (a dog is walked once at a time). Create-time
  # only; NOT a PRD Singleness invariant (that's one walker per walk, enforced
  # DB-side on accept), so a model guard is proportionate — no DB constraint.
  validate :no_active_walk_for_dog, on: :create

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
      true
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
