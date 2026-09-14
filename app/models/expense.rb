class Expense < ApplicationRecord
  belongs_to :stop
  belongs_to :trip, optional: true
  belongs_to :payment_account, optional: true

  monetize :amount_cents, with_model_currency: :amount_currency
  monetize :settled_amount_cents, with_model_currency: :settled_currency, allow_nil: true

  enum :category, { lodging: 1, meals: 2, tolls: 3, ferry: 4, attractions: 5, parking: 6, fuel: 7 }

  validates :category, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :receipt_id, uniqueness: true, allow_nil: true

  before_validation :stamp_settlement, on: :create

  def receipt?
    receipt_id.present?
  end

  def vendor_display_name
    vendor['fantasy_name'].presence || vendor['name']
  end

  def reconcile!(cents)
    update!(settled_amount_cents: cents, settled_confirmed: true)
  end

  def reporting_amount(currency)
    return settled_money if currency == settled_currency

    rate = ExchangeRate.current_reporting_rate(from: settled_currency, to: currency)
    return nil unless rate

    Money.new((settled_amount_cents * rate).round, currency)
  end

  # True once payment_account is set and settlement can actually be
  # computed — false for expenses logged before you've assigned an account.
  def settled?
    settled_amount_cents.present?
  end

  private

  def stamp_settlement
    return if payment_account.blank?

    self.settled_currency = payment_account.currency

    if amount_currency == payment_account.currency
      self.settled_amount_cents = amount_cents
      self.settled_confirmed = true
    else
      rate = ExchangeRate.current_settlement_rate(
        payment_account: payment_account, from: amount_currency, to: payment_account.currency
      )
      self.settled_amount_cents = rate ? (amount_cents * rate).round : nil
      self.settled_confirmed = false
    end
  end

  def settled_money
    settled_amount_cents ? Money.new(settled_amount_cents, settled_currency) : nil
  end
end
