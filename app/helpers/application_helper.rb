# frozen_string_literal: true

module ApplicationHelper
  def format_duration(duration)
    return t('common.not_available') if duration.nil?

    hours = duration.parts[:hours] || 0
    minutes = duration.parts[:minutes] || 0

    parts = []
    parts << "#{hours} #{t('common.hour', count: hours)}" if hours.positive?
    parts << "#{minutes} #{t('common.minute', count: minutes)}" if minutes.positive?

    parts.join(" #{t('common.and')} ")
  end
end
