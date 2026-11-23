# frozen_string_literal: true

# Migration 20251118003120 renamed osm_pois.id to old_id, but Postgres does not
# rename the column's sequence, so existing databases still have
# osm_pois_id_seq while schema.rb (dumped from them) hard-codes that name as
# the column default. A fresh `schema:load` creates the sequence under its
# conventional name, osm_pois_old_id_seq, and then fails on the default.
#
# Renaming the sequence makes the live name match what a fresh database
# creates. The column default stores the sequence by OID, so it follows the
# rename and inserts keep working. IF EXISTS makes this a no-op on databases
# that are already renamed.
class RenameOsmPoisIdSequence < ActiveRecord::Migration[8.1]
  def up
    execute 'ALTER SEQUENCE IF EXISTS osm_pois_id_seq RENAME TO osm_pois_old_id_seq'
  end

  def down
    execute 'ALTER SEQUENCE IF EXISTS osm_pois_old_id_seq RENAME TO osm_pois_id_seq'
  end
end
