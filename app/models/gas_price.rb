class GasPrice
  GASOLINE_PRICES = {
    Brasil: Money.from_amount(1.14, :usd),
    Argentina: Money.from_amount(1.00, :usd),
    Uruguay: Money.from_amount(1.95, :usd),
    Chile: Money.from_amount(1.32, :usd),
    Bolivia: Money.from_amount(0.54, :usd),
    Peru: Money.from_amount(1.08, :usd),
  }

  def self.in_local_currency(country)
    GASOLINE_PRICES[country].exchange_to(Waypoint::COUNTRY_CURRENCY[country])
  end
end