# == Schema Information
#
# Table name: telemetry_logs
#
#  id         :bigint           not null, primary key
#  mongo_id   :string           not null
#  timestamp  :datetime         not null
#  data       :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
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

  scope :with_elevation_segments, lambda { |min_change_meters: 10, min_duration_seconds: 30|
    from(<<-SQL.squish)
      (
        WITH smoothed_data AS (
          SELECT
            telemetry_logs.*,
            -- Get pressure from 3 seconds ago for smoothing
            FIRST_VALUE((data->>'bmp581_pressure')::numeric) OVER (
              ORDER BY timestamp
              RANGE BETWEEN interval '3 seconds' PRECEDING AND CURRENT ROW
            ) as pressure_3sec_ago,
            FIRST_VALUE(timestamp) OVER (
              ORDER BY timestamp
              RANGE BETWEEN interval '3 seconds' PRECEDING AND CURRENT ROW
            ) as timestamp_3sec_ago,
            AVG((data->>'gps_speed')::numeric) OVER (
              ORDER BY timestamp
              RANGE BETWEEN interval '3 seconds' PRECEDING AND CURRENT ROW
            ) as avg_speed_3sec
          FROM telemetry_logs
        ),
        with_calcs AS (
          SELECT
            *,
            CASE
              WHEN pressure_3sec_ago IS NOT NULL
                AND pressure_3sec_ago > 0
                AND (data->>'bmp581_pressure')::numeric > 0
                AND timestamp != timestamp_3sec_ago
              THEN 44330.0 * (POWER(
                pressure_3sec_ago / (data->>'bmp581_pressure')::numeric,
                0.1903
              ) - 1)
              ELSE NULL
            END as baro_altitude_change_m,
            CASE
              WHEN EXTRACT(EPOCH FROM (timestamp - timestamp_3sec_ago)) > 0
                AND pressure_3sec_ago IS NOT NULL
                AND pressure_3sec_ago > 0
                AND timestamp != timestamp_3sec_ago
              THEN (44330.0 * (POWER(
                pressure_3sec_ago / (data->>'bmp581_pressure')::numeric,
                0.1903
              ) - 1)) / EXTRACT(EPOCH FROM (timestamp - timestamp_3sec_ago))
              ELSE NULL
            END as baro_vertical_speed_mps
          FROM smoothed_data
        ),
        with_direction AS (
          SELECT
            *,
            -- Determine if climbing, descending, or flat
            CASE
              WHEN baro_vertical_speed_mps > 0.1 THEN 'climbing'
              WHEN baro_vertical_speed_mps < -0.1 THEN 'descending'
              ELSE 'flat'
            END as elevation_direction,
            -- Detect direction changes to create segment boundaries
            CASE
              WHEN LAG(
                CASE
                  WHEN baro_vertical_speed_mps > 0.1 THEN 'climbing'
                  WHEN baro_vertical_speed_mps < -0.1 THEN 'descending'
                  ELSE 'flat'
                END
              ) OVER (ORDER BY timestamp) !=
                CASE
                  WHEN baro_vertical_speed_mps > 0.1 THEN 'climbing'
                  WHEN baro_vertical_speed_mps < -0.1 THEN 'descending'
                  ELSE 'flat'
                END
              THEN 1 ELSE 0
            END as direction_change
          FROM with_calcs
        ),
        with_segments AS (
          SELECT
            *,
            -- Create segment IDs by summing direction changes
            SUM(direction_change) OVER (ORDER BY timestamp) as segment_id
          FROM with_direction
        ),
        segment_stats AS (
          SELECT
            segment_id,
            MIN(timestamp) as segment_start,
            MAX(timestamp) as segment_end,
            elevation_direction,
            COUNT(*) as point_count,
            SUM(baro_altitude_change_m) as total_elevation_change,
            EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))) as duration_seconds,
            AVG(avg_speed_3sec) as avg_speed,
            MIN((data->>'bmp581_pressure')::numeric) as min_pressure,
            MAX((data->>'bmp581_pressure')::numeric) as max_pressure,
            -- Calculate approximate distance traveled
            AVG(avg_speed_3sec) * EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))) as distance_meters
          FROM with_segments
          WHERE elevation_direction IN ('climbing', 'descending')
          GROUP BY segment_id, elevation_direction
          HAVING
            ABS(SUM(baro_altitude_change_m)) >= #{min_change_meters}
            AND EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))) >= #{min_duration_seconds}
        )
        SELECT
          with_segments.*,
          segment_stats.segment_start,
          segment_stats.segment_end,
          segment_stats.total_elevation_change,
          segment_stats.duration_seconds,
          segment_stats.avg_speed,
          segment_stats.distance_meters,
          segment_stats.point_count,
          -- Calculate average grade for the segment
          CASE
            WHEN segment_stats.distance_meters > 0
            THEN (segment_stats.total_elevation_change / segment_stats.distance_meters) * 100
            ELSE NULL
          END as segment_avg_grade
        FROM with_segments
        INNER JOIN segment_stats ON with_segments.segment_id = segment_stats.segment_id
      ) AS telemetry_logs
    SQL
  }

  # Helper scope to get just the segment summaries
  scope :elevation_segment_summaries, lambda { |min_change_meters: 10, min_duration_seconds: 30|
    from(<<-SQL.squish)
    (
      WITH smoothed_data AS (
        SELECT
          telemetry_logs.*,
          FIRST_VALUE((data->>'bmp581_pressure')::numeric) OVER (
            ORDER BY timestamp
            RANGE BETWEEN interval '3 seconds' PRECEDING AND CURRENT ROW
          ) as pressure_3sec_ago,
          FIRST_VALUE(timestamp) OVER (
            ORDER BY timestamp
            RANGE BETWEEN interval '3 seconds' PRECEDING AND CURRENT ROW
          ) as timestamp_3sec_ago,
          AVG((data->>'gps_speed')::numeric) OVER (
            ORDER BY timestamp
            RANGE BETWEEN interval '3 seconds' PRECEDING AND CURRENT ROW
          ) as avg_speed_3sec
        FROM telemetry_logs
      ),
      with_calcs AS (
        SELECT
          *,
          CASE
            WHEN pressure_3sec_ago IS NOT NULL
              AND pressure_3sec_ago > 0
              AND (data->>'bmp581_pressure')::numeric > 0
              AND timestamp != timestamp_3sec_ago
            THEN 44330.0 * (POWER(
              pressure_3sec_ago / (data->>'bmp581_pressure')::numeric,
              0.1903
            ) - 1)
            ELSE NULL
          END as baro_altitude_change_m,
          CASE
            WHEN EXTRACT(EPOCH FROM (timestamp - timestamp_3sec_ago)) > 0
              AND pressure_3sec_ago IS NOT NULL
              AND pressure_3sec_ago > 0
              AND timestamp != timestamp_3sec_ago
            THEN (44330.0 * (POWER(
              pressure_3sec_ago / (data->>'bmp581_pressure')::numeric,
              0.1903
            ) - 1)) / EXTRACT(EPOCH FROM (timestamp - timestamp_3sec_ago))
            ELSE NULL
          END as baro_vertical_speed_mps
        FROM smoothed_data
      ),
      with_direction AS (
        SELECT
          *,
          CASE
            WHEN baro_vertical_speed_mps > 0.1 THEN 'climbing'
            WHEN baro_vertical_speed_mps < -0.1 THEN 'descending'
            ELSE 'flat'
          END as elevation_direction,
          CASE
            WHEN LAG(
              CASE
                WHEN baro_vertical_speed_mps > 0.1 THEN 'climbing'
                WHEN baro_vertical_speed_mps < -0.1 THEN 'descending'
                ELSE 'flat'
              END
            ) OVER (ORDER BY timestamp) !=
              CASE
                WHEN baro_vertical_speed_mps > 0.1 THEN 'climbing'
                WHEN baro_vertical_speed_mps < -0.1 THEN 'descending'
                ELSE 'flat'
              END
            THEN 1 ELSE 0
          END as direction_change
        FROM with_calcs
      ),
      with_segments AS (
        SELECT
          *,
          SUM(direction_change) OVER (ORDER BY timestamp) as segment_id
        FROM with_direction
      )
      SELECT
        segment_id,
        MIN(id) as start_log_id,
        MAX(id) as end_log_id,
        MIN(timestamp) as segment_start,
        MAX(timestamp) as segment_end,
        MIN(elevation_direction) as elevation_direction,
        COUNT(*) as point_count,
        ROUND(SUM(baro_altitude_change_m)::numeric, 2) as total_elevation_change,
        ROUND(EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp)))::numeric, 1) as duration_seconds,
        ROUND(AVG(avg_speed_3sec)::numeric, 2) as avg_speed_mps,
        ROUND((AVG(avg_speed_3sec) * EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))))::numeric, 2) as distance_meters,
        ROUND(
          CASE
            WHEN AVG(avg_speed_3sec) * EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))) > 0
            THEN (SUM(baro_altitude_change_m) / (AVG(avg_speed_3sec) * EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))))) * 100
            ELSE NULL
          END::numeric, 2
        ) as avg_grade_percent,
        MIN((data->>'gps_latitude')::numeric) as start_lat,
        MIN((data->>'gps_longitude')::numeric) as start_lon,
        MAX((data->>'gps_latitude')::numeric) as end_lat,
        MAX((data->>'gps_longitude')::numeric) as end_lon
      FROM with_segments
      WHERE elevation_direction IN ('climbing', 'descending')
      GROUP BY segment_id, elevation_direction
      HAVING
        ABS(SUM(baro_altitude_change_m)) >= #{min_change_meters}
        AND EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))) >= #{min_duration_seconds}
      ORDER BY segment_start
    ) AS telemetry_logs
    SQL
  }

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
