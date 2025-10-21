class CalculateRouteJob < ApplicationJob
  queue_as :default

  def perform(route_id)
    route = Route.find(route_id)
    return unless route

    route.calculate_route
    sleep(2)
    route.reload
    route.import_duration
  rescue StandardError => e
    Rails.logger.error("Failed to calculate route for Route ID #{route_id}: #{e.message}")
  end
end
