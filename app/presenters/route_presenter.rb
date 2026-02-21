# frozen_string_literal: true

# Presentation layer for a Route.
#
# Keeps view-oriented logic — external URLs, formatted labels, display
# helpers — out of the model. Instantiate with a route and call methods
# from views, serializers, or API responses.
#
# The presenter does not inherit from anything and holds no state beyond
# the route it wraps, making it straightforward to test without a request
# context.
#
# @example In a view
#   <% presenter = RoutePresenter.new(route) %>
#   <%= link_to 'Open in Google Maps', presenter.google_maps_url, target: '_blank' %>
#
# @example In a serializer
#   RoutePresenter.new(route).google_maps_url
#
class RoutePresenter
  # Google Maps Directions API base URL
  GOOGLE_MAPS_BASE_URL = 'https://www.google.com/maps/dir/?api=1'

  # @param route [Route]
  def initialize(route)
    @route = route
  end

  # Builds a Google Maps Directions URL for the route.
  #
  # Origin and destination are the route's start and end waypoints.
  # Any waypoints in between are passed as pipe-separated intermediate stops.
  # An empty intermediate waypoints list is handled gracefully — Google Maps
  # accepts a waypoints parameter with no values.
  #
  # @return [String] fully-formed Google Maps URL
  def google_maps_url
    "#{GOOGLE_MAPS_BASE_URL}&#{query_string}"
  end

  private

  def query_string
    URI.encode_www_form(
      origin: formatted_coord(waypoint_start),
      destination: formatted_coord(waypoint_end),
      waypoints: intermediate_waypoints_param
    )
  end

  # Middle waypoints (everything between first and last), pipe-separated.
  # Returns an empty string when there are no intermediate stops, which is
  # still valid for the Google Maps URL.
  #
  # @return [String]
  def intermediate_waypoints_param
    intermediates = waypoints[1..-2] || []
    intermediates.map { |w| formatted_coord(w) }.join('|')
  end

  # @param waypoint [Waypoint]
  # @return [String] "lat,lon"
  def formatted_coord(waypoint)
    "#{waypoint.lonlat.latitude},#{waypoint.lonlat.longitude}"
  end

  def waypoint_start
    @route.waypoint_start
  end

  def waypoint_end
    @route.waypoint_end
  end

  def waypoints
    @waypoints ||= @route.waypoints.to_a
  end
end
