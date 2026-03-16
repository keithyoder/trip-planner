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

  def precip_color_class(prob)
    case prob
    when 0..15  then 'text-success'
    when 16..35 then 'text-success'
    when 36..55 then 'text-warning'
    when 56..75 then 'text-warning'
    else             'text-danger'
    end
  end
end
