# frozen_string_literal: true

require 'bunny'

# TelemetryRabbitMQConsumer
#
# Handles RabbitMQ connection and message consumption for telemetry data.
# This class is responsible for establishing and maintaining the RabbitMQ connection,
# consuming messages from the queue, and delegating message processing to a handler.
#
# == Responsibilities
#
# * Establishes and maintains RabbitMQ connection with automatic recovery
# * Consumes messages from the 'telemetry_sync' queue
# * Handles connection failures with retry logic
# * Provides graceful shutdown capabilities
# * Acknowledges or rejects messages based on processing results
#
# == Configuration
#
# Reads RabbitMQ connection settings from environment variables:
# * RABBITMQ_HOST - Server hostname (default: localhost)
# * RABBITMQ_PORT - Server port (default: 5672)
# * RABBITMQ_VHOST - Virtual host (default: trip_sync)
# * RABBITMQ_USER - Username (default: sync_user)
# * RABBITMQ_PASSWORD - Password (required)
#
# == Usage
#
#   consumer = TelemetryRabbitMQConsumer.new do |message|
#     # Process message
#     puts "Received: #{message}"
#   end
#   consumer.start
#
class TelemetryRabbitMQConsumer # rubocop:disable Metrics/ClassLength
  RETRY_DELAY = 5
  HEARTBEAT = 60
  PREFETCH_COUNT = 1
  QUEUE_NAME = 'telemetry_sync'

  attr_reader :connection, :channel, :queue

  # Initialize the consumer with a message handler block
  #
  # @yield [message] Block that processes each message
  # @yieldparam message [Hash] The parsed message to process
  def initialize(&message_handler)
    @connection = nil
    @channel = nil
    @queue = nil
    @running = false
    @message_handler = message_handler
  end

  # Start consuming messages (blocking operation)
  #
  # This method will run indefinitely until interrupted or an unrecoverable error occurs.
  # It automatically handles reconnection on connection failures.
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

  # Stop consuming messages and close connections
  def stop
    @running = false
    shutdown
  end

  private

  def setup_connection
    Rails.logger.info '[*] Connecting to RabbitMQ...'

    config = rabbitmq_config

    @connection = Bunny.new(config.merge(connection_options))
    @connection.start

    @channel = @connection.create_channel
    @channel.prefetch(PREFETCH_COUNT)

    @queue = @channel.queue(QUEUE_NAME, durable: true)

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
    message = JSON.parse(body)
    @message_handler.call(message)
    @channel.ack(delivery_info.delivery_tag)
    Rails.logger.info '[✓] Message processed'
  rescue StandardError => e
    log_error('Message processing error', e)
    @channel.nack(delivery_info.delivery_tag, false, true)
  end

  def handle_shutdown(reason)
    @running = false
    shutdown
    Rails.logger.info "[*] RabbitMQ consumer #{reason}"
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
    Rails.logger.info '[*] Shutting down RabbitMQ connection...'

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
