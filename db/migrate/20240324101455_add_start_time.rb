class AddStartTime < ActiveRecord::Migration[7.1]
  def change
    add_column :routes, :start_time, :interval
  end
end
