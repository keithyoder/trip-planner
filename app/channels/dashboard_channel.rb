# frozen_string_literal: true

class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from "dashboard_updates_#{locale}"
  end
end
