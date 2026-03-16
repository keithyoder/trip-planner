# frozen_string_literal: true

# == Schema Information
#
# Table name: weather_estimates
#
#  id                  :bigint           not null, primary key
#  lat                 :decimal(7, 2)    not null
#  lon                 :decimal(7, 2)    not null
#  planned_date        :date             not null
#  temp_mean_c         :float
#  temp_min_c          :float
#  temp_max_c          :float
#  temp_min_std        :float
#  temp_max_std        :float
#  precipitation_mm    :float
#  precipitation_std   :float
#  precip_probability  :integer
#  windspeed_kmh       :float
#  windspeed_std       :float
#  windspeed_max_kmh   :float
#  windspeed_max_std   :float
#  humidity_pct                :integer
#  weathercode                 :integer
#  cloudcover_pct              :integer
#  precipitation_hours         :integer
#  precipitation_probability_max :integer
#  source              :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#  index_weather_estimates_on_location_and_date  (lat, lon, planned_date) UNIQUE
#
class WeatherEstimate < ApplicationRecord
  # No belongs_to — keyed by (lat, lon, planned_date), not by model association.
  # Any part of the app can look up or store weather for an arbitrary coordinate.

  enum :source, { climate_normal: 'climate_normal', forecast: 'forecast' }

  validates :lat,          presence: true
  validates :lon,          presence: true
  validates :planned_date, presence: true
  validates :source,       presence: true

  # ── Lookup ────────────────────────────────────────────────────────────────

  # Find a record by coordinate and date. Coordinates are rounded to 2dp
  # to match how Weather::Historical and Weather::Forecast store them.
  #
  # @param lat  [Float]
  # @param lon  [Float]
  # @param date [Date]
  # @return [WeatherEstimate, nil]
  def self.for_location(lat, lon, date)
    find_by(
      lat: lat.to_f.round(2),
      lon: lon.to_f.round(2),
      planned_date: date
    )
  end

  # ── Staleness ─────────────────────────────────────────────────────────────

  FORECAST_TTL = 3.hours

  # Climate normals are permanent — once stored they never need refreshing.
  # Forecasts expire after FORECAST_TTL.
  def fresh?
    climate_normal? || updated_at > FORECAST_TTL.ago
  end

  def stale?
    !fresh?
  end

  # ── Conversion ────────────────────────────────────────────────────────────

  # Reconstitutes a Weather::Result from stored columns. The concern and views
  # work against Weather::Result regardless of whether data came from DB or API.
  #
  # precipitation_years is not persisted — precip_probability is stored as a
  # pre-computed integer. We patch the struct method via define_singleton_method
  # so callers use result.precip_probability without knowing the difference.
  def to_weather_result
    result = Weather::Result.new(
      lat: lat.to_f,
      lon: lon.to_f,
      date: planned_date,
      source: source.to_sym,
      temp_mean: temp_mean_c && Units::Temperature.new(temp_mean_c, units: :celsius),
      temp_min: temp_min_c  && Units::Temperature.new(temp_min_c,  units: :celsius),
      temp_max: temp_max_c  && Units::Temperature.new(temp_max_c,  units: :celsius),
      temp_min_std: temp_min_std,
      temp_max_std: temp_max_std,
      precipitation_mm: precipitation_mm,
      precipitation_std: precipitation_std,
      precipitation_years: nil,
      windspeed: windspeed_kmh && Units::Speed.new(windspeed_kmh, units: :km_per_hour),
      windspeed_std: windspeed_std,
      windspeed_max: windspeed_max_kmh && Units::Speed.new(windspeed_max_kmh, units: :km_per_hour),
      windspeed_max_std: windspeed_max_std,
      humidity_pct: humidity_pct,
      weathercode: weathercode,
      cloudcover_pct: cloudcover_pct,
      precipitation_hours: precipitation_hours,
      precipitation_probability_max: precipitation_probability_max
    )

    # Patch precip_probability to return the stored integer rather than
    # recomputing from the absent precipitation_years array.
    stored_prob = precip_probability
    result.define_singleton_method(:precip_probability) { stored_prob }

    result
  end

  # ── Persistence ───────────────────────────────────────────────────────────

  # Creates or updates the estimate for a location+date from a Weather::Result.
  # Upserts on the (lat, lon, planned_date) composite unique index — safe to
  # call from background jobs without race conditions.
  #
  # @param result [Weather::Result]
  def self.store_result(result)
    upsert(
      {
        lat: result.lat,
        lon: result.lon,
        planned_date: result.date,
        source: result.source.to_s,
        temp_mean_c: result.temp_mean&.celsius&.value&.to_f,
        temp_min_c: result.temp_min&.celsius&.value&.to_f,
        temp_max_c: result.temp_max&.celsius&.value&.to_f,
        temp_min_std: result.temp_min_std,
        temp_max_std: result.temp_max_std,
        precipitation_mm: result.precipitation_mm,
        precipitation_std: result.precipitation_std,
        precip_probability: result.precip_probability,
        windspeed_kmh: result.windspeed&.km_per_hour&.value&.to_f,
        windspeed_std: result.windspeed_std,
        windspeed_max_kmh: result.windspeed_max&.km_per_hour&.value&.to_f,
        windspeed_max_std: result.windspeed_max_std,
        humidity_pct: result.humidity_pct,
        weathercode: result.weathercode,
        cloudcover_pct: result.cloudcover_pct,
        precipitation_hours: result.precipitation_hours,
        precipitation_probability_max: result.precipitation_probability_max
      },
      unique_by: %i[lat lon planned_date],
      update_only: %i[
        source
        temp_mean_c temp_min_c temp_max_c temp_min_std temp_max_std
        precipitation_mm precipitation_std precip_probability
        precipitation_hours precipitation_probability_max
        windspeed_kmh windspeed_std windspeed_max_kmh windspeed_max_std
        humidity_pct weathercode cloudcover_pct
      ]
    )
  end
end
