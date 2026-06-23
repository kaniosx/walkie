class WalksController < ApplicationController
  include OwnerOnly

  def index
    @active_walks = current_user.owned_walks.active.includes(:dog).order(created_at: :desc)
    @past_walks   = current_user.owned_walks
                                .where(state: %w[completed cancelled])
                                .includes(:dog, :accepted_by_walker)
                                .order(created_at: :desc)
  end

  def cancel
    # Scoped to owner's own walks: 404s on a foreign or missing id.
    # Defense-in-depth on top of cancel!'s owner_id guard — intentionally
    # diverges from the unscoped Walk.find in open_requests_controller.rb,
    # which relies solely on the model guard.
    walk = current_user.owned_walks.find(params[:id])

    if walk.cancel!(current_user)
      redirect_to walks_path, notice: "Walk request cancelled."
    else
      redirect_to walks_path, alert: "This walk can no longer be cancelled."
    end
  end

  def create
    # Scoped to the owner's own active dogs: a foreign/absent/soft-deleted
    # dog_id raises RecordNotFound (404), so an owner can only request a walk
    # for a dog they currently own. Locality is copied from the profile.
    dog = current_user.dogs.active.find(params[:dog_id])
    walk = dog.walks.new(owner: current_user, city: current_user.city, postcode: current_user.postcode)

    if walk.save
      redirect_to walks_path, notice: "Walk requested for #{dog.name}."
    else
      redirect_to walks_path, alert: walk.errors.full_messages.to_sentence
    end
  end
end
