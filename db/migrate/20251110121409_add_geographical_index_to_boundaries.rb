# frozen_string_literal: true

class AddGeographicalIndexToBoundaries < ActiveRecord::Migration[7.2]
  def change
    add_index :boundaries, :geom, using: :gist
  end
end
