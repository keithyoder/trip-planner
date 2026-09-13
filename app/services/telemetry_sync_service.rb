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
# * Computes and stores barometric_altitude on each log, calibrated via
#   BarometricAltitude::Calibrator against real driving data rather than
#   a fixed standard-atmosphere constant
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
# The service broadcasts real-time updates, once per supported locale, to
# "dashboard_updates_<locale>" ActionCable channels, formatted via
# Dashboard::DataPresenter.
#
# The direction field is calculated from the heading using cardinal directions:
# N (0°), NE (45°), E (90°), SE (135°), S (180°), SW (225°), W (270°), NW (315°)
#
# == Performance Considerations
#
# * Trip detection results are cached for 5 seconds to reduce computation
# * Only broadcasts updates for recent logs (<10 seconds old) to avoid unnecessary network traffic
# * Automatically detects and saves completed trips by comparing detected vs saved trip counts

class TelemetrySyncService # rubocop:disable Metrics/ClassLength
  TRIP_DETECTION_CACHE_SECONDS = 5
  MAX_PROCESSING_DELAY = 2.minutes

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

  def upsert_telemetry_log(document)
    data = document.except('_id', 'timestamp')
    timestamp = parse_timestamp(document['timestamp'])

    if data['bmp581_pressure'] && (Time.current - timestamp) <= MAX_PROCESSING_DELAY
      data['barometric_altitude'] = BarometricAltitude::Calibrator.altitude_for(data['bmp581_pressure']).round(1)
    end

    attributes = { mongo_id: document['_id'].to_s, timestamp: timestamp, data: data }

    log = TelemetryLog.find_or_initialize_by(mongo_id: attributes[:mongo_id])
    log.assign_attributes(attributes)

    if log.save
      Rails.logger.info "[✓] Saved: #{log.mongo_id}"
      observe_for_calibration(log)
      log
    else
      Rails.logger.error "Failed to save: #{log.errors.full_messages.join(', ')}"
      raise ActiveRecord::RecordInvalid, log
    end
  end

  def observe_for_calibration(log)
    BarometricAltitude::Calibrator.observe(
      pressure: log.data['bmp581_pressure'],
      gps_altitude: log.data['gps_altitude']&.to_f,
      gps_speed_kmh: log.data['gps_speed'].to_f * 3.6,
      satellites: log.data['gps_satellites'],
      timestamp: log.timestamp
    )
  rescue StandardError => e
    log_error('Calibration observe error', e)
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

    ensure_trip_detector_initialized
    today_distance = calculate_today_distance
    travelling = false

    I18n.available_locales.each do |locale|
      data = Dashboard::DataPresenter.new(
        log,
        trip_detector: @trip_detector,
        today_distance: today_distance,
        locale: locale
      ).as_json

      travelling ||= data[:travelling]
      ActionCable.server.broadcast("dashboard_updates_#{locale}", data)
    end

    check_and_save_trip(travelling)

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
    if @was_travelling != is_currently_travelling
      Rails.logger.info "[*] Trip state changed: was_travelling=#{@was_travelling}, now=#{is_currently_travelling}"
    end

    Rails.logger.info '[*] Trip started' if !@was_travelling && is_currently_travelling

    @was_travelling = is_currently_travelling

    check_for_unsaved_trips
  end

  def check_for_unsaved_trips
    return unless @trip_detector

    detected_trips_count = @trip_detector.all_trips.length
    saved_trips_count = TripLog.today.count

    return unless detected_trips_count > saved_trips_count

    Rails.logger.info "[*] Found #{detected_trips_count - saved_trips_count} unsaved trip(s), saving..."
    save_todays_trips
  end

  def save_todays_trips
    return unless @trip_detector

    today = Time.find_zone(TelemetryLog.current_timezone).now

    detected_trips = @trip_detector.detect_trips(
      start_date: today.beginning_of_day,
      end_date: today.end_of_day,
      use_cache: true
    )

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
