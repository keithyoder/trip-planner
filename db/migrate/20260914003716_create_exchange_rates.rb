class CreateExchangeRates < ActiveRecord::Migration[7.2]
  def change
    create_table :exchange_rates do |t|
      t.references :payment_account, null: true, foreign_key: true
      t.string  :from_currency, null: false
      t.string  :to_currency,   null: false
      t.decimal :rate,          null: false, precision: 12, scale: 6

      t.timestamps
    end

    add_index :exchange_rates, %i[payment_account_id from_currency to_currency created_at],
              name: 'index_exchange_rates_settlement_lookup'
    add_index :exchange_rates, %i[from_currency to_currency created_at],
              name: 'index_exchange_rates_reporting_lookup', where: 'payment_account_id IS NULL'
  end
end
