class CreateTelemetryLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :telemetry_logs do |t|
      t.string :mongo_id, null: false
      t.datetime :timestamp, null: false
      t.jsonb :data, default: {}, null: false

      t.timestamps
    end

    add_index :telemetry_logs, :mongo_id, unique: true
    add_index :telemetry_logs, :timestamp
    add_index :telemetry_logs, :data, using: :gin
  end
end
