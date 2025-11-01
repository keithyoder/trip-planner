# frozen_string_literal: true

require_relative 'telemetry_rabbitmq_consumer'

# TelemetrySyncService
#
# A background service that processes telemetry data and syncs it to the local database.
# This service consumes telemetry logs from RabbitMQ, stores them in PostgreSQL,
# and broadcasts real-time updates to connected dashboard clients via ActionCable.
#
# == Responsibilities
#
# * Processes incoming telemetry log messages from RabbitMQ
# * Upserts telemetry logs to the local PostgreSQL database
# * Detects trip status and calculates real-time statistics
# * Broadcasts dashboard updates to connected clients for recent logs (<10 seconds old)
# * Automatically saves completed trips to the database
#
# == Configuration
#
# RabbitMQ connection is configured via environment variables (see TelemetryRabbitMQConsumer).
#
# == Usage
#
#   # Start the service (blocking)
#   TelemetrySyncService.start
#
#   # Or create and start an instance
#   service = TelemetrySyncService.new
#   service.start
#
# == Message Format
#
# Expected message format from RabbitMQ:
#   {
#     "collection": "logs",
#     "document": {
#       "_id": "mongodb_document_id",
#       "timestamp": "2025-11-01T12:00:00Z",
#       "gps_latitude": 40.7128,
#       "gps_longitude": -74.0060,
#       "gps_speed": 15.5,
#       "shtc3_temperature": 22.5,
#       ...
#     }
#   }
#
# == Dashboard Updates
#
# The service broadcasts real-time updates to the 'dashboard_updates' ActionCable channel
# with the following data structure:
#   {
#     travelling: true/false,
#     distance_km: 12.5,
#     speed_kmh: 55.8,
#     gps: { lat: 40.7128, lon: -74.0060, altitude: 10.0, ... },
#     temperature: 22.5,
#     weather: { temperature: 22.5, humidity: 65.0, pressure: 1013.2, ... },
#     timestamp: "2025-11-01T12:00:00Z"
#   }
#
# == Performance Considerations
#
# * Trip detection results are cached for 30 seconds to reduce computation
# * Only broadcasts updates for recent logs to avoid unnecessary network traffic
# * Automatically detects and saves completed trips
#
class TelemetrySyncService
  TRIP_DETECTION_CACHE_SECONDS = 5

  def self.start
    new.start
  end

  def initialize
    @consumer = nil
    @trip_detector = nil
    @last_trip_detection = nil
    @was_travelling = false
  end

  def start
    @consumer = TelemetryRabbitMQConsumer.new do |message|
      process_message(message)
    end

    @consumer.start
  end

  def stop
    @consumer&.stop
  end

  private

  def process_message(message)
    case message['collection']
    when 'logs'
      process_log(message['document'])
    else
      Rails.logger.warn "Unknown collection: #{message['collection']}"
    end
  end

  def process_log(document)
    log = upsert_telemetry_log(document)
    broadcast_dashboard_update(log)
  end

  def upsert_telemetry_log(document) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    attributes = {
      mongo_id: document['_id'].to_s,
      timestamp: parse_timestamp(document['timestamp']),
      data: document.except('_id', 'timestamp')
    }

    log = TelemetryLog.find_or_initialize_by(mongo_id: attributes[:mongo_id])
    log.assign_attributes(attributes)

    if log.save
      Rails.logger.info "[✓] Saved: #{log.mongo_id}"
      log
    else
      Rails.logger.error "Failed to save: #{log.errors.full_messages.join(', ')}"
      raise ActiveRecord::RecordInvalid, log
    end
  end

  def parse_timestamp(timestamp)
    Time.zone.parse(timestamp)
  rescue StandardError => e
    Rails.logger.error "Error parsing timestamp #{timestamp.inspect}: #{e.message}"
    Time.zone.now
  end

  def broadcast_dashboard_update(log)
    return unless recent_log?(log)
    return unless valid_gps_data?(log)

    data = build_dashboard_data(log)

    # Detect and save trip when it completes
    check_and_save_trip(data[:travelling])

    ActionCable.server.broadcast('dashboard_updates', data)

    Rails.logger.info "[✓] Broadcasted to dashboard: #{log.mongo_id}"
  rescue StandardError => e
    log_error('Broadcast error', e)
  end

  def recent_log?(log)
    log.timestamp >= 10.seconds.ago
  end

  def valid_gps_data?(log)
    log.data['gps_latitude'].present?
  end

  def build_dashboard_data(log)
    {
      travelling: currently_travelling?,
      distance_km: calculate_today_distance,
      speed_kmh: calculate_speed(log.data['gps_speed']),
      gps: extract_gps_data(log),
      temperature: log.data['shtc3_temperature']&.round(1),
      weather: extract_weather_data(log),
      timestamp: log.timestamp.iso8601
    }
  end

  def currently_travelling? # rubocop:disable Metrics/MethodLength
    # Cache trip detector to avoid repeated calculations
    now = Time.current
    if @last_trip_detection.nil? || (now - @last_trip_detection) >= TRIP_DETECTION_CACHE_SECONDS
      @trip_detector ||= TripDetector.new
      today = Time.find_zone(TelemetryLog.current_timezone).now
      @trip_detector.detect_trips(
        start_date: today.beginning_of_day,
        end_date: today,
        use_cache: true
      )
      @last_trip_detection = now

      travelling = @trip_detector.currently_travelling?
      Rails.logger.debug "[TripDetector] Currently travelling: #{travelling}"
      travelling
    else
      @trip_detector.currently_travelling?
    end
  end

  def calculate_today_distance
    # Calculate distance from loaded records
    distance_meters = TripLog.today.to_a.sum(&:distance)
    distance_meters += @trip_detector.current_trip[:total_distance] if @trip_detector&.current_trip
    (distance_meters / 1000.0).round(1)
  end

  def calculate_speed(gps_speed)
    return 0 unless gps_speed

    (gps_speed.to_f * 3.6).round(1)
  end

  def extract_gps_data(log) # rubocop:disable Metrics/AbcSize
    {
      lat: log.data['gps_latitude']&.to_f,
      lon: log.data['gps_longitude']&.to_f,
      altitude: log.data['gps_altitude']&.to_f,
      heading: log.data['gps_heading']&.to_f,
      climb: log.data['gps_climb']&.to_f,
      satellites: log.data['gps_satellites']&.to_i
    }
  end

  def extract_weather_data(log)
    {
      temperature: log.data['shtc3_temperature']&.round(1),
      humidity: log.data['shtc3_humidity']&.round(1),
      pressure: log.data['bmp581_pressure']&.round(1),
      dewpoint: log.data['shtc3_dewpoint']&.round(1)
    }
  end

  def check_and_save_trip(is_currently_travelling)
    # Log state for debugging
    if @was_travelling != is_currently_travelling
      Rails.logger.info "[*] Trip state changed: was_travelling=#{@was_travelling}, now=#{is_currently_travelling}"
    end

    # Log trip start
    Rails.logger.info '[*] Trip started' if !@was_travelling && is_currently_travelling

    @was_travelling = is_currently_travelling

    # Check if there are unsaved trips by comparing counts
    check_for_unsaved_trips
  end

  def check_for_unsaved_trips
    return unless @trip_detector

    # Get counts of detected trips vs saved trips
    detected_trips_count = @trip_detector.all_trips.length
    saved_trips_count = TripLog.today.count

    # If we have more detected trips than saved trips, save them
    return unless detected_trips_count > saved_trips_count

    Rails.logger.info "[*] Found #{detected_trips_count - saved_trips_count} unsaved trip(s), saving..."
    save_todays_trips
  end

  def save_todays_trips
    return unless @trip_detector

    today = Time.find_zone(TelemetryLog.current_timezone).now

    # Get all detected trips for today
    detected_trips = @trip_detector.detect_trips(
      start_date: today.beginning_of_day,
      end_date: today.end_of_day,
      use_cache: true
    )

    # Save all trips
    saved_trips = @trip_detector.save_trips(detected_trips)

    if saved_trips.any?
      Rails.logger.info "[✓] Saved #{saved_trips.length} trip(s) for today"
    else
      Rails.logger.warn '[!] No trips saved (may not meet minimum requirements)'
    end
  rescue StandardError => e
    log_error('Error saving trips', e)
  end

  def log_error(message, error)
    Rails.logger.error "#{message}: #{error.class} - #{error.message}"
    Rails.logger.error error.backtrace.join("\n") if error.backtrace
  end
end
