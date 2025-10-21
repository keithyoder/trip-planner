# frozen_string_literal: true

class WaypointsController < ApplicationController
  before_action :set_waypoint, only: %i[show edit update destroy]
  before_action :set_trip

  # GET /waypoints or /waypoints.json
  def index
    @waypoints = if params.key?(:ferry)
                   @trip.waypoint_distances.includes(:waypoint).where(waypoint_type: :ferry_disembarkment).order(:sequence)
                 elsif params.key?(:gas_station)
                   @trip.waypoint_distances.includes(:waypoint).where(waypoint_type: :gas_station).order(:sequence)
                 elsif params.key?(:toll)
                   @trip.waypoint_distances.includes(:waypoint).where(waypoint_type: :toll_booth).order(:sequence)
                 else
                   @trip.waypoint_distances.includes(:waypoint).order(:sequence)
                 end
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
    params.require(:waypoint).permit(:name, :sequence, :toll, :waypoint_type, :latlon)
  end
end
