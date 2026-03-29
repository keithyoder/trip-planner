# frozen_string_literal: true

class WaypointsController < ApplicationController
  before_action :set_waypoint, only: %i[show edit update destroy]
  before_action :set_trip

  # GET /waypoints or /waypoints.json
  def index
    @waypoints = @trip.waypoint_distances.order(:sequence).to_a

    waypoints = Waypoint
                .where(id: @waypoints.map(&:id))
                .to_a

    ActiveRecord::Associations::Preloader.new(
      records: waypoints,
      associations: :boundaries,
      scope: Boundary.without_geom
    ).call

    waypoints_by_id = waypoints.index_by(&:id)
    @waypoints.each { |wd| wd.waypoint = waypoints_by_id[wd.id] }

    @waypoints = filter_waypoints(@waypoints)
  end

  # GET /waypoints/1 or /waypoints/1.json
  def show; end

  # GET /waypoints/new
  def new
    @waypoint = Waypoint.new
  end

  # GET /waypoints/1/edit
  def edit; end

  # POST /waypoints or /waypoints.json
  def create
    @waypoint = Waypoint.new(waypoint_params.merge(trip: @trip))

    respond_to do |format|
      if @waypoint.save
        format.html { redirect_to trip_waypoint_url(@trip, @waypoint), notice: 'Waypoint was successfully created.' }
        format.json { render :show, status: :created, location: @waypoint }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @waypoint.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /waypoints/1 or /waypoints/1.json
  def update
    respond_to do |format|
      if @waypoint.update(waypoint_params.merge(trip: @trip))
        format.html { redirect_to trip_waypoint_url(@trip, @waypoint), notice: 'Waypoint was successfully updated.' }
        format.json { render :show, status: :ok, location: @waypoint }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @waypoint.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /waypoints/1 or /waypoints/1.json
  def destroy
    @waypoint.destroy

    respond_to do |format|
      format.html { redirect_to waypoints_url, notice: 'Waypoint was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_waypoint
    @waypoint = Waypoint.find(params[:id])
  end

  def set_trip
    @trip = Trip.find(params[:trip_id])
  end

  # Only allow a list of trusted parameters through.
  def waypoint_params
    params.require(:waypoint).permit(:name, :sequence, :waypoint_type, :latlon, :toll, :delay_hours,
                                     :delay_minutes, :profile, notes: {}).tap do |permitted_params|
      if permitted_params[:delay_hours].present? || permitted_params[:delay_minutes].present?
        hours = permitted_params.delete(:delay_hours).to_i
        minutes = permitted_params.delete(:delay_minutes).to_i
        permitted_params[:delay] = (hours * 3600) + (minutes * 60)
      end
    end
  end

  def filter_waypoints(waypoints)
    if params.key?(:ferry)
      waypoints.select { |w| w.waypoint_type == 'ferry_disembarkment' }
    elsif params.key?(:gas_station)
      waypoints.select { |w| w.waypoint_type == 'gas_station' }
    elsif params.key?(:toll)
      waypoints.select { |w| w.waypoint_type == 'toll_booth' }
    else
      waypoints
    end
  end
end
