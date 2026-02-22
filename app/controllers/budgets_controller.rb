# app/controllers/budgets_controller.rb

class BudgetsController < ApplicationController
  before_action :set_trip

  def show
    @budget = Budget.new(@trip, currency: params[:currency]&.to_sym || :brl)
  end

  private

  def set_trip
    @trip = Trip.find(params[:trip_id])
  end
end
