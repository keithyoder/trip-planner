# db/migrate/20260912010003_create_expenses.rb
class CreateExpenses < ActiveRecord::Migration[7.2]
  def change
    create_table :expenses do |t|
      t.references :stop, null: false, foreign_key: true
      t.references :trip, null: true, foreign_key: true
      t.references :payment_account, null: true, foreign_key: true

      t.integer :category, null: false

      t.monetize :amount, currency: { default: nil, null: false }

      t.string  :receipt_id
      t.string  :receipt_url
      t.text    :raw_receipt_xml
      t.jsonb   :items,  default: [], null: false
      t.jsonb   :vendor, default: {}, null: false

      t.integer :settled_amount_cents
      t.string  :settled_currency
      t.boolean :settled_confirmed, null: false, default: false

      t.timestamps
    end

    add_index :expenses, :receipt_id, unique: true
    add_index :expenses, :items,  using: :gin
    add_index :expenses, :vendor, using: :gin
    add_index :expenses, :category
  end
end
