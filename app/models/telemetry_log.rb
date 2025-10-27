class TelemetryLog < ApplicationRecord
  validates :mongo_id, presence: true, uniqueness: true
  validates :timestamp, presence: true

  # Scopes
  scope :recent, -> { order(timestamp: :desc) }
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
end
