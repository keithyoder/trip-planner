# app/models/exchange_rate.rb
class ExchangeRate < ApplicationRecord
  belongs_to :payment_account, optional: true

  validates :from_currency, :to_currency, presence: true
  validates :rate, numericality: { greater_than: 0 }

  # Set when you know the actual rate a specific account applies --
  # e.g. right after exchanging cash, or your card's typical spread.
  def self.set_settlement_rate!(payment_account:, from_currency:, to_currency:, rate:)
    create!(payment_account: payment_account, from_currency: from_currency, to_currency: to_currency, rate: rate)
  end

  def self.current_settlement_rate(payment_account:, from:, to:)
    return 1.0 if from == to

    where(payment_account: payment_account, from_currency: from, to_currency: to)
      .order(created_at: :desc).first&.rate
  end

  # General reference rates, not tied to any account -- fine to update
  # periodically from a live source (money-open-exchange-rates) rather
  # than manually, since these never represent real settled money.
  def self.set_reporting_rate!(from_currency:, to_currency:, rate:)
    create!(payment_account: nil, from_currency: from_currency, to_currency: to_currency, rate: rate)
  end

  def self.current_reporting_rate(from:, to:)
    return 1.0 if from == to

    direct = where(payment_account: nil, from_currency: from, to_currency: to).order(created_at: :desc).first
    return direct.rate if direct

    reverse = where(payment_account: nil, from_currency: to, to_currency: from).order(created_at: :desc).first
    reverse ? (1.0 / reverse.rate) : nil
  end
end
