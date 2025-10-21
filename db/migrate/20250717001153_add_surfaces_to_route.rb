class AddSurfacesToRoute < ActiveRecord::Migration[7.1]
  def change
    add_column :routes, :surfaces, :jsonb, default: {}
  end
end
