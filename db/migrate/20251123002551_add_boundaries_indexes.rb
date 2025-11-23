# frozen_string_literal: true

class AddBoundariesIndexes < ActiveRecord::Migration[7.2]
  def change
    add_index :boundaries_waypoints, %i[waypoint_id boundary_id],
              name: 'index_boundaries_waypoints_on_waypoint_and_boundary'

    add_index :boundaries_waypoints, %i[boundary_id waypoint_id],
              name: 'index_boundaries_waypoints_on_boundary_and_waypoint'

    add_index :boundaries, :level,
              name: 'index_boundaries_on_level'
  end
end
