# frozen_string_literal: true

class RoutesController < ApplicationController # rubocop:disable Metrics/ClassLength
  before_action :set_trip
  before_action :set_route, only: %i[edit update destroy calculate generate_day_plan]
  helper WaypointsHelper

  # GET /routes or /routes.json
  def index
    all_waypoints = @trip.waypoints.to_a

    @routes = @trip.route_sequences.order(:sequence).to_a

    route_ids = @routes.map(&:route_id)
    routes_by_id = Route.without_geom
                        .where(id: route_ids)
                        .preload(:waypoint_start, :waypoint_end)
                        .index_by(&:id)

    @routes.each do |rs|
      rs.trip                = @trip
      rs.route               = routes_by_id[rs.route_id]
      rs.preloaded_waypoints = all_waypoints
    end
  end

  # GET /routes/1 or /routes/1.json
  def show
    set_route_for_show
    set_adjacent_route_ids
    schedule_weather_fetch_if_needed
  end

  # GET /routes/new
  def new
    @route = @trip.routes.new
  end

  # GET /routes/1/edit
  def edit; end

  # POST /routes or /routes.json
  def create
    @route = @trip.routes.build(route_params_with_duration)

    respond_to do |format|
      if @route.save
        format.html { redirect_to trip_route_url(@trip, @route), notice: 'Route was successfully created.' }
        format.json { render :show, status: :created, location: @route }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @route.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /routes/1 or /routes/1.json
  def update
    respond_to do |format|
      if @route.update(route_params_with_duration)
        format.html { redirect_to trip_route_url(@trip, @route), notice: 'Route was successfully updated.' }
        format.json { render :show, status: :ok, location: @route }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @Route.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /routes/1 or /routes/1.json
  def destroy
    @route.destroy

    respond_to do |format|
      format.html { redirect_to routes_url, notice: 'route was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  # POST /routes/1/calculate
  def calculate
    CalculateRouteJob.perform_later(@route.id)

    respond_to do |format|
      format.html { redirect_to edit_trip_route_url(@trip, @route), notice: 'Route calculation has been queued.' }
      format.json { head :no_content }
    end
  end

  def generate_day_plan
    @route.update!(day_plan_status: 'generating')
    GenerateDayPlanJob.perform_later(@route.id)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          'day-plan-content',
          partial: 'routes/day_plan',
          locals: { route: @route }
        )
      end
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_route
    @route = @trip.routes.find(params[:id])
  end

  def set_trip
    @trip = Trip.find(params[:trip_id])
  end

  # Only allow a list of trusted parameters through.
  def set_route_for_show
    @route = @trip.routes.includes(
      :route_sequence, :waypoint_start, :waypoint_end, :trip
    ).find(params[:id])
  end

  def set_adjacent_route_ids
    route_ids = @trip.routes
                     .joins(:route_sequence)
                     .order('route_sequences.sequence')
                     .pluck(:id)
    current_idx    = route_ids.index(@route.id)
    @prev_route_id = route_ids[current_idx - 1] if current_idx.positive?
    @next_route_id = route_ids[current_idx + 1]
  end

  def schedule_weather_fetch_if_needed
    return unless @route.start_time && @route.geom.present?

    missing = waypoints_missing_weather
    return if missing.empty?

    missing.each { |wp| wp.instance_variable_set(:@weather, nil) }
    @weather_forecast_pending = true
    missing.each { |wp| FetchWaypointWeatherJob.perform_later(wp.id, route_id: @route.id) }
  end

  def waypoints_missing_weather
    @route.waypoints.reject(&:routing?).reject do |wp|
      next true unless wp.lonlat && wp.planned_date

      estimate = WeatherEstimate.for_location(
        wp.lonlat.y.to_f.round(2), wp.lonlat.x.to_f.round(2), wp.planned_date
      )
      estimate&.fresh?
    end
  end

  def route_params
    params.require(:route).permit(
      :name,
      :sequence,
      :waypoint_start_id,
      :waypoint_end_id,
      :start_time_days,
      :start_time_hours,
      :start_time_minutes
    )
  end

  def route_params_with_duration # rubocop:disable Metrics/AbcSize
    permitted = route_params

    # Convert duration fields to seconds
    if permitted[:start_time_days].present? || permitted[:start_time_hours].present? || permitted[:start_time_minutes].present?
      days = (permitted[:start_time_days].presence || 0).to_i
      hours = (permitted[:start_time_hours].presence || 0).to_i
      minutes = (permitted[:start_time_minutes].presence || 0).to_i

      permitted[:start_time] = (days * 86_400) + (hours * 3600) + (minutes * 60)
    end

    # Remove the virtual attributes
    permitted.except(:start_time_days, :start_time_hours, :start_time_minutes)
  end
end
