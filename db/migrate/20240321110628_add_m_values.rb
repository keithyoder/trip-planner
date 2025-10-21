class AddMValues < ActiveRecord::Migration[7.0]
  def change
    change_column :routes, :geom, :line_string, has_z: true, has_m: true, srid: 4326, geographic: true,
      using: 'ST_Force4D(geom::geometry)'
  end
end
