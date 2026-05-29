class HomeController < ApplicationController
  # Minimal authenticated landing (root). Inherits require_authentication, so it
  # doubles as the protected route exercised by the Phase 4 auth-redirect test.
  # Real post-auth destinations arrive with the user-facing slices (S-01+).
  def index
  end
end
