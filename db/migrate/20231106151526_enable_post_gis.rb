# frozen_string_literal: true

class EnablePostGis < ActiveRecord::Migration[7.0]
  def change
    enable_extension 'postgis'
  end
end
