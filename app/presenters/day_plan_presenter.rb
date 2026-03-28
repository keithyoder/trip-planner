# frozen_string_literal: true

# app/presenters/day_plan_presenter.rb
#
# Compiles a markdown day plan for a route from waypoint notes on the fly.
# No persistence or background job required — call #to_markdown in the view.
#
# == Usage
#
# A single instance can serve all locales — waypoints and boundaries are loaded
# once and shared across all locale calls:
#
#   presenter = DayPlanPresenter.new(route)
#   presenter.available_locales             # => ["en", "pt"]
#   presenter.to_markdown(locale: 'en')     # => "## **Diamantina → ...**\n\n..."
#   presenter.to_whatsapp(locale: 'pt')     # => "*Diamantina → ...*\n\n..."
#   presenter.empty?(locale: 'es')          # => true
#
# The +locale+ parameter on each method defaults to the locale passed to the
# constructor (which itself defaults to +I18n.locale+), so existing call sites
# that instantiate one presenter per locale continue to work unchanged.
#
# == Notes
#
# Waypoints without a note in the requested locale are skipped.
# Boundaries are eager-loaded without geometry once per instance to avoid N+1 queries.
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
#     surfaces: "Road surfaces"
#
class DayPlanPresenter
  # @param route  [Route]
  # @param locale [String] default locale for methods that don't specify one
  def initialize(route, locale: I18n.locale.to_s)
    @route  = route
    @locale = locale.to_s
  end

  # Returns a markdown string for the given locale.
  #
  # @param locale [String]
  # @return [String, nil]
  def to_markdown(locale: @locale)
    locale = locale.to_s
    return nil if empty?(locale: locale)

    ([header, meta(locale: locale), surfaces_table(locale: locale)] + sections(locale: locale))
      .compact
      .join("\n\n")
  end

  # Converts the day plan to WhatsApp-compatible formatting.
  #
  # WhatsApp supports: *bold*, _italic_, ~strikethrough~, `monospace`
  # It does not support labeled links, so [text](url) becomes "text: url".
  # Markdown headers are converted to bold text.
  #
  # @param locale [String]
  # @return [String, nil]
  def to_whatsapp(locale: @locale) # rubocop:disable Metrics/MethodLength
    locale = locale.to_s
    return nil if empty?(locale: locale)

    to_markdown(locale: locale)
      .gsub(/^#{Regexp.escape('## ')}(.+)/) { "*#{::Regexp.last_match(1).gsub(/\*\*(.+?)\*\*/, '\1')}*" }
      .gsub(/^#{Regexp.escape('#')}+ (.+)/, '*\1*')
      .gsub(/\*\*(.+?)\*\*/, '*\1*')
      .gsub(/__(.+?)__/, '*\1*')
      .gsub(/\*(.+?)\*/, '*\1*')      # already bold-formatted, no-op but catches stragglers
      .gsub(/_(.+?)_/, '_\1_')        # single underscore italic — WhatsApp native
      .gsub(/\[([^\]]+)\]\(([^)]+)\)/, '\1: \2')
      .gsub(/^[-*] /, '• ')
      .gsub(/^\d+\. /, '• ')
      .strip
  end

  # Returns true if there is no content to display for the given locale.
  #
  # @param locale [String]
  # @return [Boolean]
  def empty?(locale: @locale)
    locale = locale.to_s
    meta(locale: locale).blank? && sections(locale: locale).empty?
  end

  # @param locale [String]
  # @return [Boolean]
  def present?(locale: @locale)
    !empty?(locale: locale.to_s)
  end

  # Returns the list of locales for which this route has content.
  # Checks all three supported locales against the already-loaded waypoints —
  # no additional queries fired.
  #
  # @return [Array<String>]
  def available_locales
    %w[en es pt].select { |l| present?(locale: l) }
  end

  private

  # -- Output building -------------------------------------------------------

  # Route header — locale-independent (place names are not translated).
  #
  # @return [String]
  def header
    "## **#{@route.waypoint_start.name} → #{@route.waypoint_end.name}**"
  end

  # Builds the meta line: date · distance · driving time · Google Maps link.
  # Memoized per locale so repeated calls within the same render are free.
  #
  # @param locale [String]
  # @return [String]
  def meta(locale: @locale)
    locale = locale.to_s
    @meta ||= {}
    @meta[locale] ||= begin
      parts = []
      if formatted_date(locale: locale)
        parts << "**#{t('day_plan.date',
                        locale: locale)}:** #{formatted_date(locale: locale)}"
      end
      if formatted_distance(locale: locale)
        parts << "**#{t('day_plan.distance',
                        locale: locale)}:** ~#{formatted_distance(locale: locale)}"
      end
      if formatted_driving_time
        parts << "**#{t('day_plan.driving_time',
                        locale: locale)}:** ~#{formatted_driving_time} (#{t('day_plan.excluding_stops',
                                                                            locale: locale)})"
      end
      parts << "[#{t('day_plan.google_maps', locale: locale)}](#{google_maps_url})" if google_maps_url

      parts.join(' · ')
    end
  end

  # Renders significant surfaces as a small text block below the meta line.
  # Returns nil if surface data is unavailable or only one surface type exists.
  # Surface distances are formatted in the locale's preferred unit.
  #
  # Example output:
  #   **Road surfaces**
  #   Asphalt · 87 mi · 92%
  #   Unknown · 4 mi · 4%
  #   Paved · 3 mi · 3%
  #
  # @param locale [String]
  # @return [String, nil]
  def surfaces_table(locale: @locale)
    locale   = locale.to_s
    surfaces = @route.significant_surfaces
    return nil if surfaces.size <= 1

    unit = t('units.distance', locale: locale).to_sym
    abbr = t('units.distance_abbr', locale: locale)

    rows = surfaces.map do |s|
      name    = s.surface_type.to_s.tr('_', ' ').capitalize
      value   = s.distance.to_units(unit).value.round(0)
      percent = s.percent.round
      "#{name} · #{value} #{abbr} · #{percent}%"
    end

    (["**#{t('day_plan.surfaces', locale: locale)}**"] + rows).join("\n")
  end

  # Returns waypoint notes for the given locale, skipping blank entries.
  # Memoized per locale.
  #
  # @param locale [String]
  # @return [Array<String>]
  def sections(locale: @locale)
    locale = locale.to_s
    @sections ||= {}
    @sections[locale] ||= waypoints.filter_map do |waypoint|
      note = waypoint.notes&.dig(locale)
      next if note.blank?

      note
    end
  end

  # -- Formatting helpers ----------------------------------------------------

  # @param locale [String]
  # @return [String, nil]
  def formatted_date(locale: @locale)
    date = @route.route_sequence&.date
    return nil unless date

    I18n.l(date, format: :day_plan, locale: locale.to_s)
  end

  # @param locale [String]
  # @return [String, nil]
  def formatted_distance(locale: @locale)
    distance = @route.route_sequence&.distance
    return nil unless distance

    locale = locale.to_s
    unit   = t('units.distance', locale: locale).to_sym  # :miles or :km
    abbr   = t('units.distance_abbr', locale: locale)    # "mi" or "km"
    value  = distance.to_units(unit).value.round

    "#{value} #{abbr}"
  end

  # Driving time is locale-independent (numeric formatting only).
  # Rounds up to the nearest 15-minute increment.
  #
  # @return [String, nil]
  def formatted_driving_time
    @formatted_driving_time ||= begin
      duration = @route.route_sequence&.driving_duration
      return nil unless duration

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
  end

  # Google Maps URL is locale-independent.
  #
  # @return [String, nil]
  def google_maps_url
    @google_maps_url ||= RoutePresenter.new(@route).google_maps_url
  end

  # -- Data loading ----------------------------------------------------------

  # Loads all waypoints for the route with boundaries preloaded in a single
  # query. Memoized so all locale calls share the same records.
  #
  # @return [Array<Waypoint>]
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

  # Thin wrapper around I18n.t that passes the given locale explicitly.
  #
  # @param key    [String]
  # @param locale [String]
  # @return [String]
  def t(key, locale: @locale)
    I18n.t(key, locale: locale)
  end
end
