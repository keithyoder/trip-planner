class CreatePaymentAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_accounts do |t|
      t.string  :name,     null: false
      t.string  :kind,     null: false
      t.string  :currency, null: false
      t.boolean :active,   null: false, default: true

      t.timestamps
    end
  end
end
