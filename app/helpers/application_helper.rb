# frozen_string_literal: true

module ApplicationHelper
  STATUS_BADGE_CLASSES = {
    'planning' => 'bg-secondary',
    'in_progress' => 'bg-success',
    'completed' => 'bg-primary'
  }.freeze

  STATUS_ICONS = {
    'planning' => 'bi-clipboard',
    'in_progress' => 'bi-car-front-fill',
    'completed' => 'bi-check-circle-fill'
  }.freeze

  # Renders a status pill badge (icon + translated label) for any model
  # with a planning/in_progress/completed status enum (Trip, Route).
  def status_badge(status, i18n_scope: 'trips.show.status')
    css_class = STATUS_BADGE_CLASSES.fetch(status.to_s, 'bg-secondary')
    icon      = STATUS_ICONS.fetch(status.to_s, 'bi-clipboard')

    content_tag(:span, class: "badge rounded-pill #{css_class}") do
      concat content_tag(:i, '', class: "bi #{icon} me-1")
      concat t("#{i18n_scope}.#{status}")
    end
  end

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
