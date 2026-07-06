class DogsController < ApplicationController
  include OwnerOnly

  before_action :set_dog, only: %i[edit update destroy]

  def index
    @dogs = current_user.dogs.active
  end

  def new
    @dog = current_user.dogs.new
  end

  def create
    @dog = current_user.dogs.new(dog_params)
    if @dog.save
      redirect_to dogs_path, notice: "Dog added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @dog.update(dog_params)
      redirect_to dogs_path, notice: "Dog updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @dog.walks.active.exists?
      redirect_to dogs_path,
        alert: "#{@dog.name} has an active walk — cancel or wait for it to complete before removing."
      return
    end
    @dog.deactivate!
    redirect_to dogs_path, notice: "#{@dog.name} was removed."
  end

  private
    # Always scope through current_user.dogs so a foreign or absent id raises
    # RecordNotFound (404) — structurally no cross-owner access.
    def set_dog
      @dog = current_user.dogs.find(params[:id])
    end

    # Remove (deactivated_at) and ownership (user_id) are never mass-assignable.
    def dog_params
      params.require(:dog).permit(:name, :breed, :weight, :notes)
    end
end
