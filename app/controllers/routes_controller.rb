class RoutesController < ApplicationController
  before_action :set_route, only: %i[ show edit update destroy ]
  before_action :set_trip

  # GET /routes or /routes.json
  def index
    @routes = @trip.route_sequences.all.order(:sequence)
  end

  # GET /routes/1 or /routes/1.json
  def show
  end

  # GET /routes/new
  def new
    @route = @trip.routes.new
  end

  # GET /routes/1/edit
  def edit
  end

  # POST /routes or /routes.json
  def create
    @route = @trip.routes.new(route_params)

    respond_to do |format|
      if @route.save
        format.html { redirect_to trip_route_url(@trip, @route), notice: "Route was successfully created." }
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
      if @Route.update(route_params)
        format.html { redirect_to trip_route_url(@trip, @route), notice: "Route was successfully updated." }
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
      format.html { redirect_to routes_url, notice: "route was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_route
      @route = Route.find(params[:id])
    end

    def set_trip
      @trip = Trip.find(params[:trip_id])
    end

    # Only allow a list of trusted parameters through.
    def route_params
      params.require(:route).permit(:name, :sequence, :waypoint_start_id, :waypoint_end_id)
    end
end
