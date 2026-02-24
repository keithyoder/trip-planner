# frozen_string_literal: true

class UpdateRouteElevationsToVersion2 < ActiveRecord::Migration[7.2]
  def change
    update_view :route_elevations, version: 2, revert_to_version: 1
  end
end
