class ApplicationController < ActionController::Base
  include Authentication

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private
    def not_found
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end

    # A malformed lat/lng (non-numeric, array param, etc.) must never reach a
    # SQL bind value or Rails.cache's #to_f as garbage — coerce to a Float or
    # nil. `exception: false` also swallows the TypeError an Array param
    # would otherwise raise.
    def coerce_coordinate(value)
      Float(value, exception: false)
    end
end
