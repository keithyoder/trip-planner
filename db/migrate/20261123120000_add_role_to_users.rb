# frozen_string_literal: true

# 0 = viewer (read-only), 1 = admin (can edit). New users default to viewer so
# an invite never grants edit rights by accident. Everyone who exists when this
# runs was invited before roles existed, i.e. is the owner, so they become admins;
# demote anyone who should only watch from the console.
class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :role, :integer, null: false, default: 0
    execute 'UPDATE users SET role = 1'
  end

  def down
    remove_column :users, :role
  end
end
