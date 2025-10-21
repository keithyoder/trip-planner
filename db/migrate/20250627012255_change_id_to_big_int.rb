class ChangeIdToBigInt < ActiveRecord::Migration[7.1]
  def change
    change_column :boundaries, :admin_node_id, :bigint
  end
end
