# frozen_string_literal: true

class RouteElevation < ActiveRecord::Base
  belongs_to :route
  attribute :distance, :distance

  self.primary_key = [:route_id, :index]

  def readonly?
    true
  end
end
