class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def up
    # display_name is optional; city/postcode are required (collected at sign-up,
    # see S-02 plan). Add nullable first so the column can be created on the
    # populated table, backfill any pre-existing rows (dev/test data only — no
    # real users yet per roadmap baseline), then enforce NOT NULL.
    add_column :users, :display_name, :string
    add_column :users, :city, :string
    add_column :users, :postcode, :string

    User.reset_column_information
    User.where(city: nil).update_all(city: "Unknown")
    User.where(postcode: nil).update_all(postcode: "00-000")

    change_column_null :users, :city, false
    change_column_null :users, :postcode, false
  end

  def down
    remove_column :users, :postcode
    remove_column :users, :city
    remove_column :users, :display_name
  end
end
