class CreateRouteTracks < ActiveRecord::Migration[7.1]
  def change
    create_view :route_tracks
  end
end
