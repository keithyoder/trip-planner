class CreateOsmPois < ActiveRecord::Migration[7.1]
  def change
    create_table :osm_pois do |t|
      t.string :name
      t.integer :poi_type
      t.string :city
      t.string :country
      t.string :district
      t.string :housenumber
      t.string :milestone
      t.string :postcode
      t.string :province
      t.string :state
      t.string :street
      t.st_point :geom, srid: 4326, geographic: true

      t.timestamps
    end
  end
end
