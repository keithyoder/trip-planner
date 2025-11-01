class TelemetryLog < ApplicationRecord
  validates :mongo_id, presence: true, uniqueness: true
  validates :timestamp, presence: true

  # Scopes
  scope :recent, -> { order(timestamp: :desc) }
  scope :with_gps, -> { where("data->>'gps_latitude' IS NOT NULL AND data->>'gps_longitude' IS NOT NULL") }
  scope :today, -> { where('timestamp >= ?', Time.zone.now.beginning_of_day) }
  scope :between, ->(start_time, end_time) { where(timestamp: start_time..end_time) }

  # Query by data fields
  scope :with_field, ->(field, value) { where("data->>'#{field}' = ?", value.to_s) }
  scope :field_greater_than, ->(field, value) { where("(data->>'#{field}')::float > ?", value) }
  scope :field_less_than, ->(field, value) { where("(data->>'#{field}')::float < ?", value) }

  # Convenience methods for common fields
  def temperature
    data['temperature']&.to_f
  end

  def humidity
    data['humidity']&.to_f
  end

  def pressure
    data['pressure']&.to_f
  end

  def get_field(field)
    data[field]
  end

  # Stats methods
  def self.avg_field(field)
    average("(data->>'#{field}')::float")
  end

  def self.max_field(field)
    maximum("(data->>'#{field}')::float")
  end

  def self.min_field(field)
    minimum("(data->>'#{field}')::float")
  end

  def coordinates
    return nil unless gps_data?

    {
      latitude: data['gps_latitude']&.to_f,
      longitude: data['gps_longitude']&.to_f,
      altitude: data['gps_altitude']&.to_f,
      timestamp: timestamp
    }
  end

  def gps_data?
    data['gps_latitude'].present? && data['gps_longitude'].present?
  end

  def self.current_location
    log = with_gps.recent.first
    log&.coordinates
  end

  def self.current_timezone
    Rails.cache.fetch('telemetry_log/current_timezone', expires_in: 1.minute) do
      location = current_location
      return nil unless location

      Boundary.containing_point(
        location[:latitude], location[:longitude]
      ).where.not(timezone: nil).order(level: :desc).pluck(:timezone).first
    end
  end
end
