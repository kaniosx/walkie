class AddCoordinatesToWalks < ActiveRecord::Migration[8.1]
  def change
    # Nullable at the DB level (like postcode was) — required at the model
    # level for new rows. No backfill: only REQUESTED walks are ever queried
    # via open_nearby, and none predate this change.
    add_column :walks, :latitude, :float
    add_column :walks, :longitude, :float

    add_index :walks, "ll_to_earth(latitude, longitude)",
      using: :gist,
      where: "latitude IS NOT NULL AND longitude IS NOT NULL",
      name: "index_walks_on_earth_coordinates"
  end
end
