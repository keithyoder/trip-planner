# app/models/payment_account.rb
class PaymentAccount < ApplicationRecord
  has_many :expenses

  enum :kind, { cash: 'cash', credit_card: 'credit_card', debit_card: 'debit_card', bank_transfer: 'bank_transfer' }

  validates :name, :currency, presence: true
end
