# frozen_string_literal: true

class AddNotesToWaypoints < ActiveRecord::Migration[7.2]
  def change
    add_column :waypoints, :notes, :jsonb, default: {}
  end
end
