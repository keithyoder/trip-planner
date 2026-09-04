# frozen_string_literal: true

class CreateEnvironmentLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :environment_logs do |t|
      t.datetime :bucket_start, null: false
      t.datetime :bucket_end, null: false
      t.integer :sample_count, null: false, default: 0

      t.references :trip, foreign_key: true, null: true

      t.string :timezone

      t.decimal :temperature, precision: 5, scale: 2
      t.decimal :humidity, precision: 5, scale: 2
      t.decimal :pressure, precision: 7, scale: 2
      t.decimal :uv_index, precision: 4, scale: 2

      t.timestamps
    end

    add_index :environment_logs, :bucket_start, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          SELECT AddGeometryColumn('environment_logs', 'location', 4326, 'POINT', 3);
        SQL
      end
    end
  end
end
