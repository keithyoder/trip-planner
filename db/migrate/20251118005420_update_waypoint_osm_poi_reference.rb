# frozen_string_literal: true

# Migration to update foreign key
class UpdateWaypointOsmPoiReference < ActiveRecord::Migration[7.2]
  def change
    # Add new column for osm_id reference
    add_column :waypoints, :osm_poi_osm_id, :string

    # Migrate existing references
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE waypoints#{' '}
          SET osm_poi_osm_id = osm_pois.osm_id
          FROM osm_pois
          WHERE waypoints.osm_poi_id = osm_pois.old_id
        SQL
      end
    end

    # Optional: remove old column after verifying data
    # remove_column :waypoints, :osm_poi_id

    # Add index
    add_index :waypoints, :osm_poi_osm_id
  end
end
