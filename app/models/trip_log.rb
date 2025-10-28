# frozen_string_literal: true

class TripLog < ApplicationRecord
  has_many :telemetry_logs, dependent: :nullify
  belongs_to :trip, optional: true

  validates :start_time, presence: true, uniqueness: true
  validates :end_time, presence: true
  validates :geom, presence: true

  validate :end_time_after_start_time

  scope :recent, -> { order(start_time: :desc) }
  scope :today, -> { where('start_time >= ?', Time.zone.now.beginning_of_day) }
  scope :on_date, ->(date) { where('start_time >= ? AND start_time < ?', date.beginning_of_day, date.end_of_day) }
  scope :between, ->(start_date, end_date) { where(start_time: start_date..end_date) }
  scope :unmatched, -> { where(trip_id: nil) }

  # Spatial queries
  scope :near, lambda { |lat, lon, distance_meters|
    where('ST_DWithin(geom, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)', lon, lat, distance_meters)
  }

  scope :intersecting, lambda { |wkt_polygon|
    where('ST_Intersects(geom, ST_GeomFromText(?, 4326))', wkt_polygon)
  }

  before_save :set_default_name, if: -> { name.blank? }

  # Calculated from timestamps
  def duration
    (end_time - start_time).to_i
  end

  def duration_minutes
    (duration / 60.0).round(1)
  end

  def duration_hours
    (duration / 3600.0).round(2)
  end

  # Calculate distance from geometry (always accurate)
  def distance
    return 0 unless geom

    @distance ||= self.class.connection.select_value(
      "SELECT ST_Length(geom::geography) FROM trip_logs WHERE id = #{id}"
    )&.to_f || 0
  end

  def distance_km
    (distance / 1000.0).round(2)
  end

  # Speed conversions
  def max_speed_kmh
    (max_speed * 3.6).round(1) if max_speed
  end

  def avg_speed_kmh
    (avg_speed * 3.6).round(1) if avg_speed
  end

  # Calculated from geometry
  def start_location
    return nil unless geom

    @start_location ||= begin
      result = self.class.connection.select_one(
        "SELECT ST_X(ST_StartPoint(geom::geometry)) as lon, ST_Y(ST_StartPoint(geom::geometry)) as lat
         FROM trip_logs WHERE id = #{id}"
      )

      { lat: result['lat'].to_f, lon: result['lon'].to_f } if result
    end
  end

  def end_location
    return nil unless geom

    @end_location ||= begin
      result = self.class.connection.select_one(
        "SELECT ST_X(ST_EndPoint(geom::geometry)) as lon, ST_Y(ST_EndPoint(geom::geometry)) as lat
         FROM trip_logs WHERE id = #{id}"
      )

      { lat: result['lat'].to_f, lon: result['lon'].to_f } if result
    end
  end

  def start_lat
    start_location&.dig(:lat)
  end

  def start_lon
    start_location&.dig(:lon)
  end

  def end_lat
    end_location&.dig(:lat)
  end

  def end_lon
    end_location&.dig(:lon)
  end

  def point_count
    return 0 unless geom

    @point_count ||= self.class.connection.select_value(
      "SELECT ST_NPoints(geom::geometry) FROM trip_logs WHERE id = #{id}"
    ).to_i
  end

  def points
    telemetry_logs.order(:timestamp)
  end

  # Get geometry as GeoJSON
  def geom_geojson
    return nil unless geom

    @geom_geojson ||= begin
      result = self.class.connection.select_value(
        "SELECT ST_AsGeoJSON(geom) FROM trip_logs WHERE id = #{id}"
      )
      JSON.parse(result) if result
    end
  end

  # Get geometry as WKT
  def geom_wkt
    return nil unless geom

    self.class.connection.select_value(
      "SELECT ST_AsText(geom) FROM trip_logs WHERE id = #{id}"
    )
  end

  # Get coordinates as array [[lon, lat], [lon, lat], ...]
  def coordinates
    geom_geojson&.dig('coordinates') || []
  end

  # Export as GeoJSON Feature
  def to_geojson
    {
      type: 'Feature',
      geometry: geom_geojson,
      properties: {
        id: id,
        name: name,
        start_time: start_time.iso8601,
        end_time: end_time.iso8601,
        distance_km: distance_km,
        duration_minutes: duration_minutes,
        max_speed_kmh: max_speed_kmh,
        avg_speed_kmh: avg_speed_kmh,
        point_count: point_count
      }
    }
  end

  # Build LineString from coordinates array
  def self.build_linestring(coordinates)
    return nil if coordinates.empty?

    points = coordinates.map { |coord| "#{coord[0]} #{coord[1]}" }.join(', ')
    "SRID=4326;LINESTRING(#{points})"
  end

  private

  def end_time_after_start_time
    return unless start_time && end_time

    return unless end_time <= start_time

    errors.add(:end_time, 'must be after start time')
  end

  def set_default_name
    self.name = "Trip on #{start_time.strftime('%B %d, %Y at %I:%M %p')}"
  end
end
