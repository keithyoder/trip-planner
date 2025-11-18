class AddMetadataToOsmPois < ActiveRecord::Migration[7.2]
  def change
    add_column :osm_pois, :metadata, :jsonb, default: {}

    # Add index for querying metadata
    add_index :osm_pois, :metadata, using: :gin
  end
end
