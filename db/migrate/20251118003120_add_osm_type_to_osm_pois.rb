class AddOsmTypeToOsmPois < ActiveRecord::Migration[7.0]
  def change
    # Add osm_type column to distinguish between nodes, ways, and relations
    add_column :osm_pois, :osm_type, :string, null: false, default: 'node'

    # Change id to osm_id to avoid conflicts (since OSM ways and nodes can have same ID)
    rename_column :osm_pois, :id, :old_id

    # Add osm_id column WITHOUT null constraint first
    add_column :osm_pois, :osm_id, :string

    # Populate osm_id from old_id for existing records
    reversible do |dir|
      dir.up do
        execute "UPDATE osm_pois SET osm_id = 'node_' || old_id::text WHERE osm_id IS NULL"
      end
    end

    # Now add the null constraint after data is populated
    change_column_null :osm_pois, :osm_id, false

    # Remove old index and create new composite unique index
    remove_index :osm_pois, :old_id if index_exists?(:osm_pois, :old_id)
    add_index :osm_pois, :osm_id, unique: true

    # Optionally remove old_id if you don't need it
    # remove_column :osm_pois, :old_id
  end
end
