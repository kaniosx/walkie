class DogsController < ApplicationController
  include OwnerOnly

  before_action :set_dog, only: %i[edit update]
  before_action :set_active_dog, only: %i[destroy]

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
    result = Dog.transaction do
      @dog.lock!
      if @dog.walks.active.exists?
        :blocked
      else
        @dog.deactivate!
        :ok
      end
    end
    if result == :blocked
      redirect_to dogs_path,
        alert: "#{@dog.name} has an active walk — cancel or wait for it to complete before removing."
    else
      redirect_to dogs_path, notice: "#{@dog.name} was removed."
    end
  end

  private
    def set_dog
      @dog = current_user.dogs.find(params[:id])
    end

    def set_active_dog
      @dog = current_user.dogs.active.find(params[:id])
    end

    # Remove (deactivated_at) and ownership (user_id) are never mass-assignable.
    def dog_params
      params.require(:dog).permit(:name, :breed, :weight, :notes)
    end
end
