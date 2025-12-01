# db/migrate/YYYYMMDDHHMMSS_create_holidays.rb
class CreateHolidays < ActiveRecord::Migration[7.0]
  def change
    create_table :holidays do |t|
      t.references :boundary, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :month # For fixed date holidays (1-12)
      t.integer :day   # For fixed date holidays (1-31)
      t.integer :calculation_type, default: 0, null: false
      t.integer :offset_days, default: 0 # Days offset from base date (can be negative)

      t.timestamps
    end

    add_index :holidays, %i[boundary_id name]
    add_index :holidays, :calculation_type
  end
end
