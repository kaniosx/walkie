module WalkerOnly
  extend ActiveSupport::Concern

  # Gate for Walker-only resources (the open-requests list + accept). Runs after
  # require_authentication (registered on ApplicationController), so current_user
  # is present here; a non-Walker is redirected before any resource lookup.
  included do
    before_action :require_walker
  end

  private
    def require_walker
      redirect_to root_path, alert: "Only Walkers can do that." unless current_user&.walker?
    end
end
