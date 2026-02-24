# frozen_string_literal: true

class CalculateRouteJob < ApplicationJob
  queue_as :default

  def perform(route_id)
    route = Route.find(route_id)
    return unless route

    Routing::OrsService.new(route).calculate
    sleep(2)
    route.reload
    Routing::DurationImporter.new(route).import
    CalculateFuelJob.perform_later(route.trip_id)
  rescue StandardError => e
    Rails.logger.error("Failed to calculate route for Route ID #{route_id}: #{e.message}")
  end
end
