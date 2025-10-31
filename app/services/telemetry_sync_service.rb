# frozen_string_literal: true

require 'bunny'
require 'json'

class TelemetrySyncService
  RETRY_DELAY = 5
  HEARTBEAT = 60
  PREFETCH_COUNT = 1
  TRIP_DETECTION_CACHE_SECONDS = 30

  def self.start
    new.start
  end

  def initialize
    @connection = nil
    @channel = nil
    @queue = nil
    @running = false
    @trip_detector = nil
    @last_trip_detection = nil
  end

  def start # rubocop:disable Metrics/MethodLength
    @running = true

    while @running
      begin
        setup_connection
        consume_messages
      rescue Interrupt
        handle_shutdown('stopped by user')
      rescue Bunny::TCPConnectionFailed => e
        handle_error('Connection failed', e)
      rescue StandardError => e
        handle_error('Unexpected error', e)
      end
    end
  end

  def broadcast_dashboard_update(log)
    return unless valid_gps_data?(log)

    data = build_dashboard_data(log)

    ActionCable.server.broadcast('dashboard_updates', data)

    Rails.logger.info "[✓] Broadcasted to dashboard: #{log.mongo_id}"
  rescue StandardError => e
    log_error('Broadcast error', e)
  end

  private

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

  def currently_travelling?
    # Cache trip detector to avoid repeated calculations
    if @last_trip_detection.nil? || @last_trip_detection < TRIP_DETECTION_CACHE_SECONDS.seconds.ago
      @trip_detector ||= TripDetector.new
      @trip_detector.detect_trips(
        start_date: Time.zone.now.beginning_of_day,
        end_date: Time.zone.now,
        use_cache: true
      )
      @last_trip_detection = Time.zone.now
    end

    @trip_detector.currently_travelling?
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

  def setup_connection
    Rails.logger.info '[*] Connecting to RabbitMQ...'

    config = rabbitmq_config

    @connection = Bunny.new(config.merge(connection_options))
    @connection.start

    @channel = @connection.create_channel
    @channel.prefetch(PREFETCH_COUNT)

    @queue = @channel.queue('telemetry_sync', durable: true)

    Rails.logger.info "[✓] Connected: #{@queue.message_count} messages waiting"
  end

  def rabbitmq_config
    {
      host: ENV.fetch('RABBITMQ_HOST', 'localhost'),
      port: ENV.fetch('RABBITMQ_PORT', 5672).to_i,
      vhost: ENV.fetch('RABBITMQ_VHOST', 'trip_sync'),
      user: ENV.fetch('RABBITMQ_USER', 'sync_user'),
      password: ENV.fetch('RABBITMQ_PASSWORD')
    }
  end

  def connection_options
    {
      heartbeat: HEARTBEAT,
      network_recovery_interval: RETRY_DELAY,
      recovery_attempts: 10,
      automatically_recover: true
    }
  end

  def consume_messages
    Rails.logger.info '[*] Waiting for messages. Press Ctrl+C to exit'

    @queue.subscribe(block: true, manual_ack: true) do |delivery_info, _properties, body|
      process_message_with_ack(delivery_info, body)
    end
  end

  def process_message_with_ack(delivery_info, body)
    process_message(body)
    @channel.ack(delivery_info.delivery_tag)
    Rails.logger.info '[✓] Message processed'
  rescue StandardError => e
    log_error('Message processing error', e)
    @channel.nack(delivery_info.delivery_tag, false, true)
  end

  def process_message(body)
    message = JSON.parse(body)

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

  def handle_shutdown(reason)
    @running = false
    shutdown
    Rails.logger.info "[*] TelemetrySyncService #{reason}"
  end

  def handle_error(message, error)
    log_error(message, error)
    shutdown
    retry_connection if @running
  end

  def retry_connection
    Rails.logger.info "[*] Retrying in #{RETRY_DELAY} seconds..."
    sleep RETRY_DELAY
  end

  def log_error(message, error)
    Rails.logger.error "#{message}: #{error.class} - #{error.message}"
    Rails.logger.error error.backtrace.join("\n") if error.backtrace
  end

  def shutdown
    Rails.logger.info '[*] Shutting down...'

    close_channel
    close_connection

    Rails.logger.info '[✓] Shutdown complete'
  end

  def close_channel
    @channel&.close if @channel&.open?
  rescue StandardError => e
    Rails.logger.error "Error closing channel: #{e.message}"
  end

  def close_connection
    @connection&.close if @connection&.open?
  rescue StandardError => e
    Rails.logger.error "Error closing connection: #{e.message}"
  end
end
