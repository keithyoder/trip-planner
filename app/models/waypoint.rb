# frozen_string_literal: true

# == Schema Information
#
# Table name: waypoints
#
#  id            :bigint           not null, primary key
#  name          :string
#  address       :string
#  sequence      :integer
#  lonlat        :geography        point, 4326
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  waypoint_type :integer
#  toll          :decimal(, )
#  delay         :integer
#  osm_poi_id    :bigint
#  trip_id       :bigint
#
class Waypoint < ApplicationRecord
  include Waypoints::Weather

  belongs_to :trip
  has_and_belongs_to_many :boundaries
  belongs_to :osm_poi, foreign_key: :osm_poi_osm_id, primary_key: :osm_id, optional: true
  has_one :waypoint_distance, foreign_key: :id

  attribute :distance, :distance

  GEO_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

  enum :waypoint_type, {
    overnight: 1,
    lunch: 2,
    ferry_boarding: 3,
    ferry_disembarkment: 4,
    toll_booth: 5,
    border_crossing: 6,
    gas_station: 7,
    attraction: 8,
    routing: 9,
    parking: 10,
    bank: 11,
    laundry: 12
  }

  PROFILES = %w[
    driving-car
    driving-hgv
    foot-hiking
    cycling-regular
    cycling-mountain
    transit
  ].freeze

  # Returns true when the waypoint is arriving via transit (bus, train, etc.).
  # Transit legs have no ORS route — geometry and directions are omitted.
  def transit?
    profile == 'transit'
  end

  geocoded_by :address do |record, results|
    result = results.first

    record.address = result.address
    record.lonlat = GEO_FACTORY.point(result.longitude, result.latitude)
  end

  after_create_commit { assign_boundaries }
  after_update_commit { assign_boundaries if saved_change_to_lonlat? }
  after_create_commit { recalculate_affected_route }
  after_update_commit { recalculate_affected_route if saved_change_to_lonlat? }

  scope :no_level, lambda { |level|
    where("id not in (SELECT waypoint_id FROM boundaries_waypoints JOIN boundaries ON boundaries_waypoints.boundary_id = boundaries.id WHERE level = #{level})")
  }

  def route
    @route ||= Route.find_by_waypoint(self)
  end

  def route_sequence
    route&.route_sequence
  end

  def currency
    CountryCurrency.for(country)
  end

  def formatted_toll
    return nil unless toll && currency

    Money.new(toll, currency).format
  end

  def country
    @country ||= if boundaries.loaded?
                   boundaries.find { |b| b.level == 2 }&.name.to_s
                 else
                   boundaries.where(level: 2).pluck(:name).join(' ')
                 end
  end

  def state
    if boundaries.loaded?
      boundaries.select { |b| b.level == 4 }.map(&:name).join(' ')
    else
      boundaries.where(level: 4).pluck(:name).join(' ')
    end
  end

  def location
    if boundaries.loaded?
      boundaries.sort_by(&:level).map(&:name).join(', ')
    else
      boundaries.without_geom.sort_by(&:level).map(&:name).join(', ')
    end
  end

  def timezone
    @timezone ||= if boundaries.loaded?
                    boundaries
                      .select { |b| b.timezone.present? }
                      .max_by(&:level)
                      &.timezone
                  else
                    boundaries.where.not(timezone: nil).order(level: :desc).pluck(:timezone).first
                  end
  end

  def solar_position(date = Date.today)
    @solar_position ||= SolarPosition.new(date, lonlat, timezone)
  end

  def notes_for(locale = I18n.locale)
    return nil if notes.blank?

    notes[locale.to_s].presence || notes[I18n.default_locale.to_s].presence
  end

  def rendered_notes(locale = I18n.locale)
    markdown = notes_for(locale)
    return nil if markdown.blank?

    MarkdownRenderer.render(markdown)
  end

  def latlon=(coordinates)
    latlon = coordinates.split(',')
    send(:lonlat=, GEO_FACTORY.point(latlon[1], latlon[0]))
  end

  def latlon
    return nil unless lonlat

    "#{lonlat.y}, #{lonlat.x}"
  end

  def self.find_boundary(level)
    Waypoints::BoundaryAssigner.assign_missing(levels: [level])
  end

  def self.calculate_sequence_for_position(trip, route, lat, lon)
    waypoint_start = route.waypoint_start
    waypoint_end   = route.waypoint_end

    return 1 unless waypoint_start && waypoint_end

    point_info = route.closest_point_info(lat, lon)
    fraction   = point_info[:fraction]

    existing_waypoints = trip.waypoints
                             .where('sequence > ? AND sequence < ?', waypoint_start.sequence, waypoint_end.sequence)
                             .order(:sequence)

    if existing_waypoints.empty?
      return (waypoint_start.sequence + (fraction * (waypoint_end.sequence - waypoint_start.sequence))).round
    end

    prev_waypoint = waypoint_start
    prev_fraction = 0.0

    existing_waypoints.each do |wp|
      next unless wp.lonlat

      wp_fraction = route.closest_point_info(wp.lonlat.y, wp.lonlat.x)[:fraction]

      if fraction < wp_fraction
        fraction_percent = (fraction - prev_fraction) / (wp_fraction - prev_fraction)
        new_sequence = prev_waypoint.sequence + (fraction_percent * (wp.sequence - prev_waypoint.sequence)).round
        new_sequence += 1 if new_sequence == prev_waypoint.sequence
        new_sequence -= 1 if new_sequence == wp.sequence
        return new_sequence
      end

      prev_waypoint = wp
      prev_fraction = wp_fraction
    end

    fraction_percent = (fraction - prev_fraction) / (1.0 - prev_fraction)
    prev_waypoint.sequence + (fraction_percent * (waypoint_end.sequence - prev_waypoint.sequence)).round
  end

  def assign_boundaries
    Waypoints::BoundaryAssigner.new(self).assign
  end

  def recalculate_affected_route
    CalculateRouteJob.perform_later(route.id) if route
  end
end
