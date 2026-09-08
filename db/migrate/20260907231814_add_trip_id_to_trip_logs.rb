class AddTripIdToTripLogs < ActiveRecord::Migration[7.2]
  def change
    add_reference :trip_logs, :trip, null: true, foreign_key: true
  end
end
