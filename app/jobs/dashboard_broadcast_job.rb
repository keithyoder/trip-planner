# frozen_string_literal: true

class DashboardBroadcastJob < ApplicationJob
  queue_as :default

  def perform
    latest_log = TelemetryLog.order(timestamp: :desc).first
    return unless latest_log

    Turbo::StreamsChannel.broadcast_replace_to(
      'dashboard',
      target: 'dashboard-content',
      partial: 'dashboard/content',
      locals: { latest_log: latest_log }
    )
  end
end
