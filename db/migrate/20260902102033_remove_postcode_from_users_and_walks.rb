class RemovePostcodeFromUsersAndWalks < ActiveRecord::Migration[8.1]
  def up
    remove_column :users, :postcode, :string, null: false
    remove_column :walks, :postcode, :string
  end

  # postcode is permanently retired (geolocation-matching plan) -- there's
  # nothing to restore it from, and Rails' auto-generated down would
  # re-add users.postcode NOT NULL with no default, which fails against any
  # row created after this migration ran. Fail loudly and intentionally
  # instead of a confusing Postgres NOT NULL violation.
  def down
    raise ActiveRecord::IrreversibleMigration, "postcode is permanently removed; see context/changes/geolocation-matching/plan.md"
  end
end
