class ExpensesController < ApplicationController
  before_action :set_stop

  def from_receipt
    result = Receipt::ImportService.new(
      stop: @stop,
      url: params[:receipt_url],
      category: params[:category]
    ).call

    if result.success?
      redirect_to edit_stop_path(@stop), notice: t('.success', amount: result.expense.amount.format)
    else
      redirect_to edit_stop_path(@stop), alert: t('.failure', error: result.error)
    end
  end

  private

  def set_stop
    @stop = Stop.find(params[:stop_id])
  end
end
