# frozen_string_literal: true

class CreateTripTracks < ActiveRecord::Migration[7.1]
  def change
    create_view :trip_tracks
  end
end
