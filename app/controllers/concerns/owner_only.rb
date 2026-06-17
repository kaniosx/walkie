module OwnerOnly
  extend ActiveSupport::Concern

  # Gate for Owner-only resources (dogs, walk requests). Runs after
  # require_authentication (registered on ApplicationController), so current_user
  # is present here; a non-Owner is redirected before any resource lookup.
  included do
    before_action :require_owner
  end

  private
    def require_owner
      redirect_to root_path, alert: "Only Owners can do that." unless current_user&.owner?
    end
end
