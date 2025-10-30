# frozen_string_literal: true

class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from 'dashboard_updates'
    # Or for user-specific: stream_from "dashboard_#{current_user.id}"
  end

  def unsubscribed
    # Cleanup when channel is unsubscribed
  end
end
