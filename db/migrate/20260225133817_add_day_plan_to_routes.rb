class AddDayPlanToRoutes < ActiveRecord::Migration[7.2]
  def change
    add_column :routes, :day_plan, :jsonb, default: {}
    add_column :routes, :day_plan_status, :string, default: 'none'
  end
end
