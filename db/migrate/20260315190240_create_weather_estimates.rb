# frozen_string_literal: true

# db/migrate/XXXXXXXXXXXXXX_create_weather_estimates.rb
class CreateWeatherEstimates < ActiveRecord::Migration[7.1]
  def change
    create_table :weather_estimates do |t|
      # Natural key — coordinates rounded to 2dp (~1km, within ERA5's 0.25° grid)
      # plus calendar date. No foreign key to any model — any part of the app
      # can look up weather for an arbitrary location and date.
      t.decimal :lat,          precision: 7, scale: 2, null: false
      t.decimal :lon,          precision: 7, scale: 2, null: false
      t.date    :planned_date,                         null: false

      # Temperature — mean, min, max and their standard deviations
      t.float   :temp_mean_c
      t.float   :temp_min_c
      t.float   :temp_max_c
      t.float   :temp_min_std
      t.float   :temp_max_std

      # Precipitation — average daily total, std dev, pre-computed probability
      t.float   :precipitation_mm
      t.float   :precipitation_std
      t.integer :precip_probability # 0–100, % of years with ≥5mm

      # Wind — daily mean and daily max, each with std dev
      t.float   :windspeed_kmh
      t.float   :windspeed_std
      t.float   :windspeed_max_kmh
      t.float   :windspeed_max_std

      # Mean relative humidity — integer 0–100
      # Primarily location-driven but carries a seasonal signal (Altiplano
      # rainy season, Brazilian wet/dry seasons). No std dev needed.
      t.integer :humidity_pct

      t.integer :weathercode
      t.integer :cloudcover_pct
      t.integer :precipitation_hours
      t.integer :precipitation_probability_max

      # 'climate_normal' — ERA5 30-yr average, permanent
      # 'forecast'       — live Open-Meteo forecast, expires after 3 hours
      t.string  :source, null: false

      t.timestamps
    end

    # Composite unique index — the natural key for lookups and upserts
    add_index :weather_estimates, %i[lat lon planned_date],
              unique: true,
              name: 'index_weather_estimates_on_location_and_date'
  end
end
