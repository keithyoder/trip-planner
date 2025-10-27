# frozen_string_literal: true

namespace :telemetry do
  desc 'Start telemetry sync consumer from RabbitMQ'
  task sync: :environment do
    puts 'Starting TelemetrySyncService...'
    puts 'Press Ctrl+C to stop'

    TelemetrySyncService.start
  end
end
