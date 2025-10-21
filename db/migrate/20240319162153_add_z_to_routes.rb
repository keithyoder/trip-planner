# frozen_string_literal: true

class AddZToRoutes < ActiveRecord::Migration[7.0]
  def change
    change_column :routes, :geom, :line_string, has_z: true, srid: 4326, geographic: true,
                                                using: 'ST_Force3D(geom::geometry)'
  end
end
