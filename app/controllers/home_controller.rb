class HomeController < ApplicationController
  # Authenticated landing (root): a role-aware dashboard. Inherits
  # require_authentication, so it doubles as the protected route exercised by
  # the Phase 4 auth-redirect test.
  def index
    if current_user.owner?
      @dogs = current_user.dogs.active
      @active_walks = current_user.owned_walks.active.includes(:dog).order(created_at: :desc)
      @active_dog_ids = @active_walks.map(&:dog_id)
    elsif current_user.walker?
      @walk = Walk.where(accepted_by_walker_id: current_user.id, state: %w[accepted in_progress])
                  .includes(:dog, :owner)
                  .first
      @open_requests_count = Walk.open_in_locality(current_user.city, current_user.postcode).count
    end
  end
end
