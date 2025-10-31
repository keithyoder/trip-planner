# app/services/trip_detector.rb

class TripDetector
  EARTH_RADIUS_METERS = 6_371_000

  def initialize
    @cached_trips = []
    @last_processed_timestamp = nil
    @current_incomplete_trip = nil
    @currently_travelling = false
  end

  # Calculate distance between two GPS coordinates in meters using Haversine formula
  def haversine_distance(lat1, lon1, lat2, lon2)
    return 0 if lat1.nil? || lon1.nil? || lat2.nil? || lon2.nil?

    phi1 = to_radians(lat1)
    phi2 = to_radians(lat2)
    delta_phi = to_radians(lat2 - lat1)
    delta_lambda = to_radians(lon2 - lon1)

    a = Math.sin(delta_phi / 2)**2 +
        Math.cos(phi1) * Math.cos(phi2) * Math.sin(delta_lambda / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    EARTH_RADIUS_METERS * c
  end

  # Clear all cached trips and reset state
  def clear_cache
    @cached_trips = []
    @last_processed_timestamp = nil
    @current_incomplete_trip = nil
    @currently_travelling = false
  end

  # Detect trips for today
  def todays_trips(use_cache: true)
    detect_trips(
      start_date: Time.zone.now.beginning_of_day,
      end_date: Time.zone.now.end_of_day,
      use_cache: use_cache
    )
  end

  # Return all cached trips
  def all_trips
    @cached_trips.dup
  end

  # Detect trips from telemetry data
  def detect_trips(
    start_date: nil,
    end_date: nil,
    min_speed: 1.0,
    max_stop_duration: 300,
    min_trip_distance: 200,
    min_trip_duration: 60,
    max_stationary_distance: 10,
    use_cache: true
  )
    # Build query
    logs_query = TelemetryLog.order(:timestamp)

    if use_cache && @last_processed_timestamp.present?
      # Only query logs after last processed timestamp
      logs_query = logs_query.where('timestamp > ?', @last_processed_timestamp)
    elsif start_date
      # Full query with date range
      logs_query = logs_query.where('timestamp >= ?', start_date)
    end
    logs_query = logs_query.where('timestamp <= ?', end_date) if end_date

    # Fetch logs
    logs = logs_query.to_a

    # Return cached trips if no new logs
    if logs.empty?
      return use_cache && @cached_trips.any? ? filter_trips_by_date(@cached_trips, start_date, end_date) : []
    end

    # Initialize from cache if available
    if use_cache && @current_incomplete_trip.present?
      current_trip = @current_incomplete_trip
      last_log = current_trip[:points].last
      last_log_time = current_trip[:end_time]
      stopped_since = current_trip[:stopped_since]
    else
      current_trip = nil
      last_log = nil
      last_log_time = nil
      stopped_since = nil
    end

    new_trips = []
    next_trip_id = @cached_trips.length + 1

    logs.each do |log|
      lat = log.data['gps_latitude']&.to_f
      lon = log.data['gps_longitude']&.to_f
      speed = log.data['gps_speed']&.to_f || 0
      timestamp = log.timestamp

      # Skip invalid GPS data
      next if lat.nil? || lon.nil?

      # Calculate distance from last point
      distance_moved = 0
      if last_log
        last_lat = last_log.data['gps_latitude']&.to_f
        last_lon = last_log.data['gps_longitude']&.to_f
        distance_moved = haversine_distance(last_lat, last_lon, lat, lon)
      end

      # Check for time gap between logs
      if current_trip && last_log_time
        time_gap = timestamp - last_log_time

        # End trip if gap exceeds threshold
        if time_gap > max_stop_duration
          finalized_trip = finalize_trip(
            current_trip, next_trip_id,
            min_trip_distance, min_trip_duration
          )
          if finalized_trip
            new_trips << finalized_trip
            @cached_trips << finalized_trip
            next_trip_id += 1
          end

          current_trip = nil
          stopped_since = nil
        end
      end

      # Determine if vehicle is moving
      is_moving = speed >= min_speed

      # Additional validation: check if actually moved significantly
      if is_moving && last_log
        time_delta = last_log_time ? (timestamp - last_log_time) : 1
        is_moving = false if distance_moved < max_stationary_distance && time_delta > 5
      end

      if is_moving
        stopped_since = nil

        if current_trip.nil?
          # Start new trip
          current_trip = {
            start_time: timestamp,
            start_lat: lat,
            start_lon: lon,
            end_time: timestamp,
            end_lat: lat,
            end_lon: lon,
            max_speed: speed,
            total_distance: 0,
            points: [log]
          }
        else
          # Continue current trip
          current_trip[:total_distance] += distance_moved if distance_moved.positive?
          current_trip[:end_time] = timestamp
          current_trip[:end_lat] = lat
          current_trip[:end_lon] = lon
          current_trip[:max_speed] = [current_trip[:max_speed], speed].max
          current_trip[:points] << log
        end
      elsif current_trip
        # Vehicle stopped or stationary
        stopped_since ||= timestamp

        stop_duration = timestamp - stopped_since
        if stop_duration > max_stop_duration
          finalized_trip = finalize_trip(
            current_trip, next_trip_id,
            min_trip_distance, min_trip_duration
          )
          if finalized_trip
            new_trips << finalized_trip
            @cached_trips << finalized_trip
            next_trip_id += 1
          end

          current_trip = nil
          stopped_since = nil
        end
      end

      last_log = log
      last_log_time = timestamp
    end

    # Update state
    @last_processed_timestamp = logs.last.timestamp if logs.any?

    # Store incomplete trip for next run
    if current_trip
      current_trip[:stopped_since] = stopped_since
      @current_incomplete_trip = current_trip
      @currently_travelling = current_trip[:total_distance] > min_trip_distance \
        && current_trip[:trip_duration_seconds] > min_trip_duration
    else
      @current_incomplete_trip = nil
      @currently_travelling = false
    end

    # Return appropriate trips based on date range
    if use_cache
      filter_trips_by_date(@cached_trips, start_date, end_date)
    else
      # Handle incomplete trip at end for non-cached mode
      if current_trip
        finalized_trip = finalize_trip(
          current_trip, next_trip_id,
          min_trip_distance, min_trip_duration
        )
        new_trips << finalized_trip if finalized_trip
      end

      new_trips
    end
  end

  def current_trip_points
    return [] unless @current_trip

    @current_trip[:points].map do |log|
      lon = log.data['gps_longitude']&.to_f
      lat = log.data['gps_latitude']&.to_f
      [lat, lon] if lon && lat
    end.compact
  end

  # Generate summary statistics for trips
  def trip_summary(trips = nil)
    trips ||= @cached_trips

    if trips.empty?
      return {
        total_trips: 0,
        total_distance_km: 0,
        total_duration_hours: 0,
        avg_trip_distance_km: 0,
        avg_trip_duration_minutes: 0,
        max_speed_kmh: 0
      }
    end

    total_distance = trips.sum { |t| t[:total_distance_meters] }
    total_duration = trips.sum { |t| t[:duration_seconds] }
    max_speed = trips.map { |t| t[:max_speed_ms] }.max

    {
      total_trips: trips.length,
      total_distance_km: total_distance / 1000.0,
      total_duration_hours: total_duration / 3600.0,
      avg_trip_distance_km: (total_distance / trips.length) / 1000.0,
      avg_trip_duration_minutes: (total_duration / trips.length) / 60.0,
      max_speed_kmh: max_speed * 3.6
    }
  end

  # Check if currently on a trip
  def currently_travelling?
    @currently_travelling
  end

  def save_trip(trip_hash)
    coordinates = trip_hash[:points].map do |log|
      lon = log.data['gps_longitude']&.to_f
      lat = log.data['gps_latitude']&.to_f
      [lon, lat] if lon && lat
    end.compact

    linestring_wkt = TripLog.build_linestring(coordinates)

    TripLog.upsert(
      {
        start_time: trip_hash[:start_time],
        end_time: trip_hash[:end_time],
        max_speed: trip_hash[:max_speed_ms],
        avg_speed: trip_hash[:avg_speed_ms],
        geom: linestring_wkt,
        data: {
          trip_id: trip_hash[:trip_id]
        },
        created_at: Time.current,
        updated_at: Time.current
      },
      unique_by: :start_time # Use start_time as the unique key
    )

    # Return the trip log
    TripLog.find_by(start_time: trip_hash[:start_time])
  end

  def save_trips(trips)
    trips.map { |trip| save_trip(trip) }
  end

  def detect_and_save_trips(**options)
    trips = detect_trips(**options)
    save_trips(trips)
  end

  def self.instance
    @instance ||= new
  end

  private

  def to_radians(degrees)
    degrees * Math::PI / 180.0
  end

  def finalize_trip(current_trip, trip_id, min_trip_distance, min_trip_duration)
    trip_duration = current_trip[:end_time] - current_trip[:start_time]

    # Validate trip meets minimum requirements
    return nil if current_trip[:total_distance] < min_trip_distance ||
                  trip_duration < min_trip_duration

    {
      trip_id: trip_id,
      start_time: current_trip[:start_time],
      end_time: current_trip[:end_time],
      duration_seconds: trip_duration,
      start_location: {
        lat: current_trip[:start_lat],
        lon: current_trip[:start_lon]
      },
      end_location: {
        lat: current_trip[:end_lat],
        lon: current_trip[:end_lon]
      },
      total_distance_meters: current_trip[:total_distance],
      max_speed_ms: current_trip[:max_speed],
      avg_speed_ms: trip_duration > 0 ? current_trip[:total_distance] / trip_duration : 0,
      point_count: current_trip[:points].length,
      points: current_trip[:points]
    }
  end

  def filter_trips_by_date(trips, start_date, end_date)
    return trips if start_date.nil? && end_date.nil?

    trips.select do |trip|
      trip_start = trip[:start_time]
      next false if start_date && trip_start < start_date
      next false if end_date && trip_start > end_date

      true
    end
  end
end
