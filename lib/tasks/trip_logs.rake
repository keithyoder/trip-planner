# frozen_string_literal: true

namespace :trip_logs do # rubocop:disable Metrics/BlockLength
  desc "Detect and save today's trips"
  task detect_today: :environment do
    detector = TripDetector.new
    today = Time.find_zone(TelemetryLog.current_timezone).now

    trips = detector.detect_and_save_trips(
      start_date: today.beginning_of_day,
      end_date: today.end_of_day,
      use_cache: false
    )

    puts "Processed #{trips.length} trips for today (duplicates skipped)"
    trips.each do |trip|
      puts "  - #{trip.name}: #{trip.distance_km} km, #{trip.duration_minutes} min"
    end
  end

  desc 'Detect and save trips for a date range (safe to re-run)'
  task :detect_range, %i[start_date end_date] => :environment do |t, args|
    timezone = TelemetryLog.current_timezone

    start_date = Time.find_zone(timezone).parse(args[:start_date] || 1.day.ago.to_s)
    end_date = Time.find_zone(timezone).parse(args[:end_date] || Time.zone.now.to_s)

    detector = TripDetector.new
    trips = detector.detect_and_save_trips(
      start_date: start_date,
      end_date: end_date,
      use_cache: false
    )

    puts "Processed #{trips.length} trips from #{start_date} to #{end_date}"
    puts '(Duplicates automatically skipped)'
    trips.each do |trip|
      puts "  - #{trip.name}: #{trip.distance_km} km, #{trip.duration_minutes} min"
    end
  end
end
