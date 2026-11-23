# frozen_string_literal: true

require 'money/bank/open_exchange_rates_bank'

oxr = Money::Bank::OpenExchangeRatesBank.new
oxr.app_id = ENV['OPEN_EXCHANGE_RATES_APP_ID']
# Fetching rates is a live HTTP call (and counts against the API quota) on every
# boot. Tests don't convert currencies, and CI has no app id, so skip it there.
# A test that needs exchange rates should set explicit ones on Money.default_bank.
oxr.update_rates unless Rails.env.test?

Money.default_bank = oxr

Money.default_currency = :brl

Money.locale_backend = :currency
Money.rounding_mode = BigDecimal::ROUND_HALF_UP
