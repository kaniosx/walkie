class WalksController < ApplicationController
  include OwnerOnly

  def index
    @walks = current_user.owned_walks.includes(:dog).order(created_at: :desc)
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
