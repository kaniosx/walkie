class WalkerWalksController < ApplicationController
  include WalkerOnly

  def index
    @walk = Walk.where(accepted_by_walker_id: current_user.id, state: %w[accepted in_progress])
                .includes(:dog)
                .first
  end

  def start
    # Scoped to accepted walks owned by this walker: 404s on foreign, completed,
    # or in-progress walks (the latter would mean the start already happened).
    walk = Walk.where(accepted_by_walker_id: current_user.id, state: :accepted).find(params[:id])

    if walk.start!(current_user)
      redirect_to walker_walks_path, notice: "Walk started — you're on your way!"
    else
      redirect_to walker_walks_path, alert: "This walk can no longer be updated."
    end
  end

  def complete
    # Scoped to in-progress walks owned by this walker: 404s on anything else.
    walk = Walk.where(accepted_by_walker_id: current_user.id, state: :in_progress).find(params[:id])

    if walk.complete!(current_user)
      redirect_to open_requests_path, notice: "Walk completed. Well done!"
    else
      redirect_to walker_walks_path, alert: "This walk can no longer be updated."
    end
  end
end
