# frozen_string_literal: true

class AddHierarchy < ActiveRecord::Migration[7.0]
  def change
    enable_extension 'ltree'

    add_column :boundaries, :hierarchy, :ltree
    rename_column :boundaries, :type, :level
  end
end
