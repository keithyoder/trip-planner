# frozen_string_literal: true

class AddStatusToTrips < ActiveRecord::Migration[7.2]
  def change
    add_column :trips, :status, :integer, default: 0, null: false

    # Enforce "only one trip in progress" at the DB level, not just in the
    # app -- a partial index only covers rows where status = 1 (in_progress
    # in the enum below), so any number of planning/completed trips can
    # coexist, but a second concurrent in_progress row is rejected outright.
    add_index :trips, :status,
              unique: true,
              where: 'status = 1',
              name: 'index_trips_on_status_in_progress'
  end
end
