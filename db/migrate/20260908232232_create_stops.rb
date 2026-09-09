class CreateStops < ActiveRecord::Migration[7.2]
  def change
    create_table :stops do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :name
      t.integer :stop_type, null: false
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.geography :geom, limit: { srid: 4326, type: 'point' }, null: false
      t.text :notes

      t.timestamps
    end

    add_index :stops, %i[trip_id start_time], unique: true
  end
end