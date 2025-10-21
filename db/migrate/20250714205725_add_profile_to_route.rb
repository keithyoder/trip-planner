class AddProfileToRoute < ActiveRecord::Migration[7.1]
  def change
    add_column :routes, :profile, :string, default: "driving-car", null: false
  end
end
