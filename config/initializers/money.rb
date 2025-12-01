# frozen_string_literal: true

require 'money/bank/open_exchange_rates_bank'

oxr = Money::Bank::OpenExchangeRatesBank.new
oxr.app_id = ENV['OPEN_EXCHANGE_RATES_APP_ID']
oxr.update_rates

Money.default_bank = oxr

Money.default_currency = :brl

Money.locale_backend = :currency
Money.rounding_mode = BigDecimal::ROUND_HALF_UP
