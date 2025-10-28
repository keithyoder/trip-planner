# frozen_string_literal: true

class TripLogsController < ApplicationController
  def index
    # Get trips for date range (default to today)
    start_date = params[:start_date] ? Time.zone.parse(params[:start_date]) : Time.zone.now.beginning_of_day
    end_date = params[:end_date] ? Time.zone.parse(params[:end_date]) : Time.zone.now.end_of_day

    @trip_logs = TripLog.between(start_date, end_date).recent

    respond_to do |format|
      format.html
      format.json do
        render json: {
          type: 'FeatureCollection',
          features: @trip_logs.map(&:to_geojson)
        }
      end
    end
  end

  def show
    @trip_log = TripLog.find(params[:id])

    respond_to do |format|
      format.html
      format.json { render json: @trip_log.to_geojson }
    end
  end

  def today
    @trip_logs = TripLog.today.recent

    render json: {
      type: 'FeatureCollection',
      features: @trip_logs.map(&:to_geojson)
    }
  end
end
