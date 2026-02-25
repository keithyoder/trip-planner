# frozen_string_literal: true

# app/presenters/day_plan_presenter.rb
#
# Compiles a markdown day plan for a route from waypoint notes on the fly.
# No persistence or background job required — call #to_markdown in the view.
#
# == Usage
#
#   presenter = DayPlanPresenter.new(route, locale: 'en')
#   presenter.to_markdown   # => "## **Copacabana → Puno**\n\n..."
#   presenter.empty?        # => false
#   presenter.present?      # => true
#
# == Notes
#
# Waypoints without a note in the requested locale are skipped.
# Boundaries are eager-loaded without geometry to avoid N+1 queries.
# Note content is used as-is — add any headers or formatting in the waypoint notes directly.
#
# == Required i18n keys
#
#   date:
#     formats:
#       day_plan: "%A, %B %-d, %Y"   # => "Wednesday, April 21, 2027"
#
#   day_plan:
#     date: "Date"
#     distance: "Distance"
#     driving_time: "Driving time"
#     excluding_stops: "excluding stops"
#     google_maps: "Open in Google Maps"
#
class DayPlanPresenter
  def initialize(route, locale: I18n.locale.to_s)
    @route  = route
    @locale = locale
  end

  def to_markdown
    return nil if empty?

    ([header, meta] + sections).join("\n\n")
  end

  def empty?
    sections.empty?
  end

  def present?
    !empty?
  end

  def available_locales
    %w[en es pt].select { |l| self.class.new(@route, locale: l).present? }
  end

  private

  def header
    "## **#{@route.waypoint_start.name} → #{@route.waypoint_end.name}**"
  end

  def meta
    parts = []
    parts << "**#{t('day_plan.date')}:** #{formatted_date}"          if formatted_date
    parts << "**#{t('day_plan.distance')}:** ~#{formatted_distance}" if formatted_distance
    if formatted_driving_time
      parts << "**#{t('day_plan.driving_time')}:** ~#{formatted_driving_time} (#{t('day_plan.excluding_stops')})"
    end
    parts << "[#{t('day_plan.google_maps')}](#{google_maps_url})" if google_maps_url

    parts.join(' · ')
  end

  def formatted_date
    date = @route.route_sequence&.date
    return nil unless date

    I18n.l(date, format: :day_plan, locale: @locale)
  end

  def formatted_distance
    distance = @route.route_sequence&.distance
    return nil unless distance

    "#{distance.km.value.round} km"
  end

  def formatted_driving_time
    duration = @route.route_sequence&.driving_duration
    return nil unless duration

    # Ceiling to next 15-minute interval
    total_minutes  = (duration.to_i / 60.0).ceil
    ceiled_minutes = (total_minutes / 15.0).ceil * 15

    hours   = ceiled_minutes / 60
    minutes = ceiled_minutes % 60

    if hours.positive? && minutes.positive?
      "#{hours}h #{minutes}m"
    elsif hours.positive?
      "#{hours}h"
    else
      "#{minutes}m"
    end
  end

  def google_maps_url
    RoutePresenter.new(@route).google_maps_url
  end

  def sections
    @sections ||= waypoints.filter_map do |waypoint|
      note = waypoint.notes&.dig(@locale)
      next if note.blank?

      note
    end
  end

  def waypoints
    @waypoints ||= begin
      wps = @route.waypoints.order(:sequence).to_a
      ActiveRecord::Associations::Preloader.new(
        records: wps,
        associations: :boundaries,
        scope: Boundary.without_geom
      ).call
      wps
    end
  end

  def t(key)
    I18n.t(key, locale: @locale)
  end
end
