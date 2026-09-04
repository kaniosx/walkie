class EnableCubeAndEarthdistance < ActiveRecord::Migration[8.1]
  def change
    # earthdistance's earth_distance/ll_to_earth functions depend on cube —
    # must be enabled first.
    enable_extension "cube"
    enable_extension "earthdistance"
  end
end
