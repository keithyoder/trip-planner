# frozen_string_literal: true

# == Schema Information
#
# Table name: environment_logs
#
#  id           :bigint           not null, primary key
#  bucket_start :datetime         not null
#  bucket_end   :datetime         not null
#  sample_count :integer          default(0), not null
#  trip_id      :bigint
#  timezone     :string
#  temperature  :decimal(5, 2)    -- degrees Celsius
#  humidity     :decimal(5, 2)    -- relative humidity, percent (0-100)
#  pressure     :decimal(7, 2)    -- hectopascals (hPa)
#  uv_index     :decimal(4, 2)    -- unitless UV index (0-11+ scale)
#  location     :geography        point Z, 4326 (lon, lat, elevation in meters)
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
class EnvironmentLog < ApplicationRecord
  belongs_to :trip, optional: true

  validates :bucket_start, presence: true, uniqueness: true
  validates :bucket_end, presence: true

  scope :recent, -> { order(bucket_start: :desc) }
  scope :between, ->(start_time, end_time) { where(bucket_start: start_time..end_time) }

  def longitude
    location&.x
  end

  def latitude
    location&.y
  end

  def elevation
    location&.z
  end

  # The bucket's start time, converted into whatever timezone the vehicle
  # was actually in at the time -- falls back to bucket_start (UTC) if no
  # timezone could be resolved (e.g. no reliable GPS fix that bucket).
  def local_time
    return bucket_start unless timezone

    bucket_start.in_time_zone(timezone)
  end

  # Magnus-Tetens approximation, Celsius in and out.
  def dew_point
    return nil unless temperature && humidity

    a = 17.62
    b = 243.12
    alpha = ((a * temperature) / (b + temperature)) + Math.log(humidity / 100.0)
    ((b * alpha) / (a - alpha)).round(2)
  end

  # NWS Rothfusz regression -- only valid/meaningful above ~26.7C (80F);
  # below that the "feels like" temperature is just the actual temperature.
  def heat_index
    return nil unless temperature && humidity
    return temperature if temperature < 26.7

    t_f = (temperature * 9.0 / 5) + 32
    rh = humidity

    hi_f = -42.379 + (2.04901523 * t_f) + (10.14333127 * rh) \
           - (0.22475541 * t_f * rh) - (0.00683783 * t_f**2) \
           - (0.05481717 * rh**2) + (0.00122874 * t_f**2 * rh) \
           + (0.00085282 * t_f * rh**2) - (0.00000199 * t_f**2 * rh**2)

    ((hi_f - 32) * 5.0 / 9).round(2)
  end
end
