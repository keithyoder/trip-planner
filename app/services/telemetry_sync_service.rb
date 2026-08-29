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
# * Automatically detects and saves completed trips to the database
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
#       "gps_heading": 45.0,
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
#     travelling: true,
#     distance_km: 12.5,
#     speed_kmh: 55.8,
#     gps: {
#       lat: 40.7128,
#       lon: -74.0060,
#       altitude: 10.0,
#       heading: 45.0,
#       direction: "NE",
#       climb: 0.5,
#       satellites: 12
#     },
#     temperature: 22.5,
#     weather: {
#       temperature: 22.5,
#       humidity: 65.0,
#       pressure: 1013.2,
#       dewpoint: 15.3
#     },
#     timestamp: "2025-11-01T12:00:00Z"
#   }
#
# The direction field is calculated from the heading using cardinal directions:
# N (0°), NE (45°), E (90°), SE (135°), S (180°), SW (225°), W (270°), NW (315°)
#
# == Performance Considerations
#
# * Trip detection results are cached for 5 seconds to reduce computation
# * Only broadcasts updates for recent logs (<10 seconds old) to avoid unnecessary network traffic
# * Automatically detects and saves completed trips by comparing detected vs saved trip counts
# * Uses DashboardDataBuilder concern for consistent data formatting across the application

require 'dashboard_data_builder'

class TelemetrySyncService # rubocop:disable Metrics/ClassLength
  include DashboardDataBuilder

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

    # Ensure trip detector is initialized
    ensure_trip_detector_initialized

    # Use the concern's build_dashboard_data method
    data = build_dashboard_data(
      log,
      trip_detector: @trip_detector,
      today_distance: calculate_today_distance
    )

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

  def ensure_trip_detector_initialized
    now = Time.current
    return if @last_trip_detection && (now - @last_trip_detection) < TRIP_DETECTION_CACHE_SECONDS

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
  end

  def calculate_today_distance
    distance_meters = TripLog.today.to_a.sum { |trip| trip.distance.to_f }
    distance_meters += @trip_detector.current_trip[:total_distance] if @trip_detector&.current_trip
    Units::Distance.new(distance_meters)
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
