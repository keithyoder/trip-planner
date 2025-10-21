# frozen_string_literal: true

json.array! @waypoints, partial: 'waypoints/waypoint', as: :waypoint
