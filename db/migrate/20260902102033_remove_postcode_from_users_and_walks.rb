class RemovePostcodeFromUsersAndWalks < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :postcode, :string, null: false
    remove_column :walks, :postcode, :string
  end
end
