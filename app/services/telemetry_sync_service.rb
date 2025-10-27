require 'bunny'
require 'json'

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
        puts "\n [*] TelemetrySyncService stopped by user"
      rescue Bunny::TCPConnectionFailed => e
        Rails.logger.error "Connection failed: #{e.message}"
        puts " [✗] Connection failed: #{e.message}"
        shutdown
        if @running
          puts ' [*] Retrying in 5 seconds...'
          sleep 5
        end
      rescue StandardError => e
        Rails.logger.error "TelemetrySyncService error: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        puts " [✗] Error: #{e.message}"
        shutdown
        if @running
          puts ' [*] Retrying in 5 seconds...'
          sleep 5
        end
      end
    end
  end

  private

  def setup_connection
    puts ' [*] Connecting to RabbitMQ...'

    config = {
      host: ENV.fetch('RABBITMQ_HOST', 'localhost'),
      port: ENV.fetch('RABBITMQ_PORT', 5672).to_i,
      vhost: ENV.fetch('RABBITMQ_VHOST', 'trip_sync'),
      user: ENV.fetch('RABBITMQ_USER', 'sync_user'),
      password: ENV.fetch('RABBITMQ_PASSWORD')
    }

    puts " [*] Config: #{config[:user]}@#{config[:host]}:#{config[:port]}/#{config[:vhost]}"

    @connection = Bunny.new(
      config.merge(
        heartbeat: 60,
        network_recovery_interval: 5,
        recovery_attempts: 10,
        automatically_recover: true
      )
    )

    @connection.start
    puts ' [✓] Connected to RabbitMQ'

    @channel = @connection.create_channel
    puts ' [✓] Channel created'

    @channel.prefetch(1)

    @queue = @channel.queue('telemetry_sync', durable: true)
    puts " [✓] Queue declared: #{@queue.name} (#{@queue.message_count} messages)"

    Rails.logger.info 'TelemetrySyncService connected successfully'
  end

  def consume_messages
    puts ' [*] Waiting for messages. Press Ctrl+C to exit'

    @queue.subscribe(block: true, manual_ack: true) do |delivery_info, properties, body|
      puts ' [→] Received message'
      process_message(body)
      @channel.ack(delivery_info.delivery_tag)
      puts ' [✓] Message processed'
    rescue StandardError => e
      Rails.logger.error "Message processing error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      puts " [✗] Processing error: #{e.message}"

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
      puts " [✓] Saved: #{mongo_id} at #{timestamp}"
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
    puts ' [*] Shutting down...'

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

    puts ' [✓] Shutdown complete'
  end
end
