# frozen_string_literal: true

class CreateCoverageFeatures < ActiveRecord::Migration[7.1]
  def change
    create_table :coverage_features do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :provider, null: false        # e.g. "claro", "starlink"
      t.string :layer, null: false           # e.g. "cobertura_externa_4G_UY"
      t.string :source_feature_id            # e.g. "cobertura_externa_4G_AR.1664204"
      t.geography :geom, limit: { srid: 4326, type: 'multi_polygon' }
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :coverage_features, %i[trip_id provider layer]
    add_index :coverage_features, :geom, using: :gist
    add_index :coverage_features, %i[trip_id provider layer source_feature_id],
              unique: true, name: 'index_coverage_features_unique_feature'
  end
end
