# app/models/trip_expense.rb
# frozen_string_literal: true

# == Schema Information
#
# Table name: trip_expenses
#
#  id         :bigint           not null, primary key
#  trip_id    :bigint           not null
#  name       :string           not null
#  category   :integer          default(0), not null
#  amount     :decimal(, )      not null
#  currency   :string           default("usd"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class TripExpense < ApplicationRecord
  belongs_to :trip

  enum :category, {
    connectivity: 0,  # Starlink, SIM cards, etc.
    insurance: 1,
    documents: 2,     # visas, permits
    vehicle: 3,       # maintenance, registration
    other: 4
  }

  validates :name, presence: true
  validates :amount, numericality: { greater_than: 0 }

  def money
    Money.from_amount(amount, currency)
  end
end
