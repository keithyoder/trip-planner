# frozen_string_literal: true

# == Schema Information
#
# Table name: route_elevations
#
#  route_id  :bigint           primary key
#  index     :integer          primary key
#  latitude  :float
#  longitude :float
#  elevation :float
#  distance  :float
#
class RouteElevation < ActiveRecord::Base
  belongs_to :route
  attribute :distance, :distance

  self.primary_key = [:route_id, :index]

  def readonly?
    true
  end
end
