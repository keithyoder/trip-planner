# frozen_string_literal: true

class StopsController < ApplicationController
  before_action :set_stop

  def edit; end

  def update
    if @stop.update(stop_params)
      redirect_to trip_logs_path(date: @stop.start_time.to_date), notice: t('stops.update.success')
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_stop
    @stop = Stop.find(params[:id])
  end

  def stop_params
    params.require(:stop).permit(:name, :stop_type, :notes)
  end
end
