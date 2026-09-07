# frozen_string_literal: true

class TripLogsController < ApplicationController
  def index
    @date = params[:date].present? ? Date.parse(params[:date]) : Time.zone.today
    @trip_logs = TripLog.on_date(@date).order(:start_time).to_a
    @summary = TripLog.summary_for(@trip_logs)

    respond_to do |format|
      format.html
      format.json do
        render json: { type: 'FeatureCollection', features: @trip_logs.map(&:to_geojson) }
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
