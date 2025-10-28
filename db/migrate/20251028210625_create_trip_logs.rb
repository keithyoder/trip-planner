class CreateTripLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :trip_logs do |t|
      t.string :name
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false

      # Trip metrics
      t.decimal :max_speed, precision: 8, scale: 3  # m/s
      t.decimal :avg_speed, precision: 8, scale: 3  # m/s

      # PostGIS geometry - LineString for the trip path
      t.geometry :geom, geographic: true, srid: 4326

      # Store additional data as JSON
      t.jsonb :data, default: {}, null: false

      t.timestamps
    end

    add_index :trip_logs, :start_time, unique: true
    add_index :trip_logs, :geom, using: :gist

    # Only add this if you plan to query the data field
    # add_index :trip_logs, :data, using: :gin
  end
end
