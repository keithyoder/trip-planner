# frozen_string_literal: true

class TripsController < ApplicationController
  # before_action :authenticate_user!
  layout 'welcome'
  before_action :set_trip, only: %i[show edit update destroy]

  # GET /trips or /trips.json
  def index
    @trips = Trip.with_distance.with_duration.all
  end

  # GET /trips/1 or /trips/1.json
  def show; end

  # GET /trips/new
  def new
    @trip = Trip.new
  end

  # GET /trips/1/edit
  def edit; end

  # POST /trips or /trips.json
  def create
    @trip = Trip.new(trip_params)

    respond_to do |format|
      if @trip.save
        format.html { redirect_to trip_url(@trip), notice: 'Trip was successfully created.' }
        format.json { render :show, status: :created, location: @trip }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @trip.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /trips/1 or /trips/1.json
  def update
    respond_to do |format|
      if @trip.update(trip_params)
        format.html { redirect_to trip_url(@trip), notice: 'Trip was successfully updated.' }
        format.json { render :show, status: :ok, location: @trip }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @trip.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /trips/1 or /trips/1.json
  def destroy
    @trip.destroy!

    respond_to do |format|
      format.html { redirect_to trips_url, notice: 'Trip was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def currencies # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    @trip = Trip.find(params[:id])

    # Get unique countries from waypoint boundaries (level 2)
    @countries = Boundary
                 .select(:id, :name, :level)
                 .joins(:waypoints)
                 .where(waypoints: { trip_id: @trip.id })
                 .where(level: 2)
                 .distinct
                 .order(:name)

    # You'll need to set your default currency - this could be a user preference
    # or a trip setting. For now, I'll use BRL as an example
    @default_currency = :brl

    timestamp = Money.default_bank.rates_timestamp
    @rates_updated_at = timestamp ? Time.at(timestamp) : nil
    @exchange_rates = @countries.map do |country|
      currency = Waypoint::COUNTRY_CURRENCY[country.name.to_sym]
      next unless currency

      {
        country: country.name,
        currency: currency,
        rate: calculate_exchange_rate(@default_currency, currency),
        formatted_rate: format_exchange_rate(@default_currency, currency),
        inverse_rate: calculate_exchange_rate(currency, @default_currency),
        formatted_inverse_rate: format_exchange_rate(currency, @default_currency)
      }
    end.compact
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_trip
    @trip = Trip.with_duration.with_distance.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def trip_params
    params.require(:trip).permit(:name, :start_on, :vehicle_description, :fuel_consumption_l_per_100km)
  end

  def calculate_exchange_rate(from_currency, to_currency)
    return 1.0 if from_currency == to_currency

    # Convert 1 unit of default currency to target currency
    Money.new(100, from_currency).exchange_to(to_currency).fractional / 100.0
  end

  def format_exchange_rate(from_currency, to_currency)
    # Calculate the rate for 1 unit first
    one_unit = Money.new(100, from_currency)
    converted = one_unit.exchange_to(to_currency)
    rate = converted.fractional / 100.0

    # Determine the appropriate multiplier based on the rate
    multiplier = case rate
                 when 0...0.01      # Less than 0.01 - use 1000 units
                   1000
                 when 0.01...0.10   # Between 0.01 and 0.10 - use 100 units
                   100
                 when 0.10...0.50
                   10
                 else               # 0.10 or more - use 1 unit
                   1
                 end

    from_money = Money.new(multiplier * 100, from_currency)
    to_money = from_money.exchange_to(to_currency)

    "#{from_money.format} = #{to_money.format}"
  end
end
