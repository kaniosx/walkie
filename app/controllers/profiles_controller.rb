class ProfilesController < ApplicationController
  def show
    @user = current_user
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(profile_params)
      redirect_to profile_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    # Only the three profile fields are editable. role/email/password are never
    # permitted here — role is also immutable at the model (F-01).
    def profile_params
      params.permit(:display_name, :city)
    end
end
