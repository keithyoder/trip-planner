class CreateRouteElevations < ActiveRecord::Migration[7.1]
  def change
    create_view :route_elevations
  end
end
