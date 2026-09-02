class OpenRequestsController < ApplicationController
  include WalkerOnly

  def index
    lat = coerce_coordinate(params[:lat])
    lng = coerce_coordinate(params[:lng])
    return if lat.nil? || lng.nil?

    WalkerLocationCache.write(current_user, latitude: lat, longitude: lng)

    @walks = Walk.open_nearby(city: current_user.city, latitude: lat, longitude: lng)
                 .includes(:dog).order(created_at: :asc)
  end

  def accept
    walk = Walk.find(params[:id])

    # accept! is the atomic compare-and-swap from F-02: it returns true only if
    # THIS call won the REQUESTED→ACCEPTED race (and the caller is a walker who
    # isn't the owner). The DB walks_walker_presence CHECK is the backstop. We
    # add no locking here — we just surface the boolean.
    if walk.accept!(current_user)
      redirect_to open_requests_path, notice: "You accepted the walk for #{walk.dog.name}."
    else
      redirect_to open_requests_path, alert: "Sorry, that walk was just accepted by someone else."
    end
  end
end
