class UniqueOsmId < ActiveRecord::Migration[7.1]
  def change
    add_index :boundaries, :osm_id, unique: true
    add_column :boundaries, :timezone, :string
  end
end
