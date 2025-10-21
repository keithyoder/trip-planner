class CreateRouteSequences < ActiveRecord::Migration[7.1]
  def change
    create_view :route_sequences
  end
end
