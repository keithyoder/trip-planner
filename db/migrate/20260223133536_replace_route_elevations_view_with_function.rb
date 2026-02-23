class DropRouteElevationView < ActiveRecord::Migration[7.2]
  def up
    drop_view :route_elevations
  end

  def down
    create_view :route_elevations, version: 3, materialized: true
  end
end
