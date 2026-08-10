# frozen_string_literal: true

# app/jobs/prefetch_weather_job.rb
#
# Sidekiq job that pre-warms WeatherEstimate for every waypoint in a trip.
# Run after routes are all calculated and trip.start_on is set.
#
# == When to enqueue
#
#   Enqueue from Trip after start_on changes:
#
#     after_update_commit -> { PrefetchWeatherJob.perform_later(id) },
#       if: :saved_change_to_start_on?
#
class PrefetchWeatherJob < ApplicationJob
  queue_as :default

  retry_on ::Weather::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(trip_id)
    trip = Trip.includes(:route_sequences, waypoints: :weather_estimate).find(trip_id)

    unless trip.start_on.present?
      Rails.logger.info "[PrefetchWeatherJob] trip ##{trip_id} has no start_on date, skipping"
      return
    end

    waypoints = trip.waypoints.order(:sequence).to_a
    Rails.logger.info "[PrefetchWeatherJob] prefetching weather for #{waypoints.size} waypoints on trip ##{trip_id}"

    Waypoints::Weather.prefetch!(waypoints)

    Rails.logger.info "[PrefetchWeatherJob] done for trip ##{trip_id}"
  end
end
