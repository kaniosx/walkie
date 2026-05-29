class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    # Required, no default: every user must explicitly choose Owner or Walker
    # at registration (PRD §Access Control — "a user is one or the other").
    add_column :users, :role, :string, null: false
  end
end
