# frozen_string_literal: true

class CreateTripExpenses < ActiveRecord::Migration[7.1]
  def change
    create_table :trip_expenses do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :category, null: false, default: 0
      t.decimal :amount, null: false
      t.string :currency, null: false, default: 'usd'
      t.timestamps
    end
  end
end
