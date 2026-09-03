# frozen_string_literal: true

class AddStatusToRoutes < ActiveRecord::Migration[7.2]
  def change
    add_column :routes, :status, :integer, default: 0, null: false

    # Scoped by trip_id rather than global: in normal operation only one
    # trip is ever in_progress, so this is effectively a global constraint
    # too, but scoping it here means the DB doesn't rely on that invariant
    # holding elsewhere to stay correct.
    add_index :routes, %i[trip_id status],
              unique: true,
              where: 'status = 1',
              name: 'index_routes_on_trip_id_status_in_progress'
  end
end
