# frozen_string_literal: true

module Follow
  # One day of the trip (a route), read-only. Every day uses the planned-day
  # page for now; the "day that has passed" page will take over for completed ones.
  class RoutesController < ApplicationController
    skip_before_action :require_admin!
    layout 'public'

    def show
      route = Route.preload(:waypoint_start, :waypoint_end, :trip, :route_sequence).find(params[:id])
      @day = Follow::PlannedDay.new(route)
    end
  end
end
