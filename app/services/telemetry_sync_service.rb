# frozen_string_literal: true

require 'bunny'
require 'json'
require 'cgi'

class TelemetrySyncService
  def self.start
    new.start
  end

  def initialize
    @connection = nil
    @channel = nil
    @queue = nil
    @running = false
  end

  def start
    @running = true

    while @running
      begin
        setup_connection
        consume_messages
      rescue Interrupt
        @running = false
        shutdown
        Rails.logger.info  "\n [*] TelemetrySyncService stopped by user"
      rescue Bunny::TCPConnectionFailed => e
        Rails.logger.error "Connection failed: #{e.message}"
        Rails.logger.info  " [✗] Connection failed: #{e.message}"
        shutdown
        if @running
          Rails.logger.info ' [*] Retrying in 5 seconds...'
          sleep 5
        end
      rescue StandardError => e
        Rails.logger.error "TelemetrySyncService error: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        Rails.logger.info  " [✗] Error: #{e.message}"
        shutdown
        if @running
          Rails.logger.info ' [*] Retrying in 5 seconds...'
          sleep 5
        end
      end
    end
  end

  def broadcast_dashboard_update(log)
    return unless log.data['gps_latitude'].present?

    detector = TripDetector.new
    detector.detect_trips(
      start_date: Time.zone.now.beginning_of_day,
      end_date: Time.zone.now,
      use_cache: true
    )

    today_distance = TripLog.today.sum(&:distance)

    # Prepare data payload
    data = {
      travelling: detector.currently_travelling?,
      distance_km: (today_distance / 1000.0).round(1),
      speed_kmh: (log.data['gps_speed'].to_f * 3.6).round(1),
      gps: {
        lat: log.data['gps_latitude']&.to_f,
        lon: log.data['gps_longitude']&.to_f,
        altitude: log.data['gps_altitude']&.to_f,
        satellites: log.data['gps_satellites']&.to_i
      },
      temperature: log.data['shtc3_temperature']&.round(1),
      weather: {
        temperature: log.data['shtc3_temperature']&.round(1),
        humidity: log.data['shtc3_humidity']&.round(1),
        pressure: log.data['bmp581_pressure']&.round(1)
      },
      timestamp: log.timestamp.iso8601
    }

    # Build the Turbo Stream HTML manually
    turbo_stream = <<~HTML
      <turbo-stream action="update_dashboard" target="dashboard-widgets-left">
        <template data="#{CGI.escape_html(data.to_json)}"></template>
      </turbo-stream>
    HTML

    # Broadcast raw HTML
    ActionCable.server.broadcast(
      'dashboard',
      turbo_stream
    )

    Rails.logger.info " [✓] Broadcasted to dashboard: #{log.mongo_id}"
  rescue StandardError => e
    Rails.logger.error "Broadcast error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def setup_connection
    Rails.logger.info  ' [*] Connecting to RabbitMQ...'

    config = {
      host: ENV.fetch('RABBITMQ_HOST', 'localhost'),
      port: ENV.fetch('RABBITMQ_PORT', 5672).to_i,
      vhost: ENV.fetch('RABBITMQ_VHOST', 'trip_sync'),
      user: ENV.fetch('RABBITMQ_USER', 'sync_user'),
      password: ENV.fetch('RABBITMQ_PASSWORD')
    }

    Rails.logger.info " [*] Config: #{config[:user]}@#{config[:host]}:#{config[:port]}/#{config[:vhost]}"

    @connection = Bunny.new(
      config.merge(
        heartbeat: 60,
        network_recovery_interval: 5,
        recovery_attempts: 10,
        automatically_recover: true
      )
    )

    @connection.start
    Rails.logger.info ' [✓] Connected to RabbitMQ'

    @channel = @connection.create_channel
    Rails.logger.info ' [✓] Channel created'

    @channel.prefetch(1)

    @queue = @channel.queue('telemetry_sync', durable: true)
    Rails.logger.info " [✓] Queue declared: #{@queue.name} (#{@queue.message_count} messages)"

    Rails.logger.info 'TelemetrySyncService connected successfully'
  end

  def consume_messages
    Rails.logger.info ' [*] Waiting for messages. Press Ctrl+C to exit'

    @queue.subscribe(block: true, manual_ack: true) do |delivery_info, properties, body|
      Rails.logger.info ' [→] Received message'
      process_message(body)
      @channel.ack(delivery_info.delivery_tag)
      Rails.logger.info  ' [✓] Message processed'
    rescue StandardError => e
      Rails.logger.error "Message processing error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      Rails.logger.info  " [✗] Processing error: #{e.message}"

      # Reject and requeue
      @channel.nack(delivery_info.delivery_tag, false, true)
    end
  end

  def process_message(body)
    message = JSON.parse(body)
    collection = message['collection']
    document = message['document']

    Rails.logger.info "Processing: #{collection}"

    case collection
    when 'logs'
      process_log(document)
    else
      Rails.logger.warn "Unknown collection: #{collection}"
    end
  end

  def process_log(document)
    mongo_id = document['_id'].to_s
    timestamp = parse_timestamp(document['timestamp'])
    data = document.except('_id', 'timestamp')

    attributes = {
      mongo_id: mongo_id,
      timestamp: timestamp,
      data: data
    }

    log = TelemetryLog.find_or_initialize_by(mongo_id: attributes[:mongo_id])
    log.assign_attributes(attributes)

    if log.save
      Rails.logger.info "Saved TelemetryLog #{log.id}"
      Rails.logger.info " [✓] Saved: #{mongo_id} at #{timestamp}"

      # Broadcast to dashboard after successful save
      broadcast_dashboard_update(log)
    else
      Rails.logger.error "Failed to save: #{log.errors.full_messages.join(', ')}"
      raise ActiveRecord::RecordInvalid, log
    end
  end

  def parse_timestamp(ts)
    case ts
    when String
      Time.zone.parse(ts)
    when Numeric
      Time.zone.at(ts)
    when Hash
      # Handle MongoDB extended JSON format: {"$date" => "2025-10-26T23:37:19Z"}
      if ts['$date']
        Time.zone.parse(ts['$date'])
      else
        Rails.logger.error "Unknown timestamp hash format: #{ts.inspect}"
        Time.zone.now
      end
    else
      Rails.logger.warn "Unknown timestamp type: #{ts.class}"
      Time.zone.now
    end
  rescue StandardError => e
    Rails.logger.error "Error parsing timestamp #{ts.inspect}: #{e.message}"
    Time.zone.now
  end

  def shutdown
    Rails.logger.info ' [*] Shutting down...'

    begin
      @channel&.close if @channel&.open?
    rescue StandardError => e
      Rails.logger.error "Error closing channel: #{e.message}"
    end

    begin
      @connection&.close if @connection&.open?
    rescue StandardError => e
      Rails.logger.error "Error closing connection: #{e.message}"
    end

    Rails.logger.info ' [✓] Shutdown complete'
  end
end
