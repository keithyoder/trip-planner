class AllowNullTripIdOnStops < ActiveRecord::Migration[7.2]
  def change
    change_column_null :stops, :trip_id, true
  end
end
