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
    bank: 11
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

    record.address = result.address # Store the address used for geocoding
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

  def country
    @country ||= boundaries.where(level: 2).pluck(:name).join(' ')
  end

  def currency
    CountryCurrency.for(country)
  end

  def formatted_toll
    return nil unless toll && currency

    Money.new(toll, currency).format
  end

  def state
    boundaries.where(level: 4).pluck(:name).join(' ')
  end

  def location
    # boundaries.order(:level).pluck(:name).join(', ')
    boundaries.without_geom.sort_by(&:level).map(&:name).join(', ')
  end

  def timezone
    # Find the boundary highest (more precise) level with a timezone
    @timezone ||= boundaries.where.not(timezone: nil).order(level: :desc).pluck(:timezone).first
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

  def copy_from_osm(osm_poi_id)
    # Just delegate to the class method
    waypoint = self.class.copy_from_osm(osm_poi_id, trip_id, sequence)

    # Copy the attributes to self
    return unless waypoint

    assign_attributes(waypoint.attributes.except('id', 'created_at', 'updated_at'))
    save!
  end

  def self.copy_from_osm(osm_poi_id, trip_id, sequence)
    osm_poi = OsmPoi.find_by(osm_id: osm_poi_id)
    return unless osm_poi

    case osm_poi.poi_type.to_sym # Changed: convert enum to symbol
    when :fuel
      waypoint_type = :gas_station
      delay = 900
    when :border_crossing
      waypoint_type = :border_crossing
      delay = 1800
    when :toll
      waypoint_type = :toll_booth
      delay = 0
    when :ferry
      waypoint_type = :ferry_boarding
      delay = 1800
    when :restaurant
      waypoint_type = :lunch
      delay = 3600
    when :accommodation
      waypoint_type = :overnight
      delay = 0
    when :tourism
      waypoint_type = :attraction
      delay = 1800
    when :barrier
      waypoint_type = :attraction
      delay = 600
    when :park
      waypoint_type = :attraction
      delay = 1800
    else
      waypoint_type = :attraction
      delay = 0
    end

    trip = Trip.find(trip_id)

    taken = trip.waypoints
                .where(sequence: sequence..sequence + 50)
                .pluck(:sequence)
                .to_set

    sequence = (sequence..sequence + 50).find { |s| !taken.include?(s) } || sequence + 51

    # Back up if we've landed on the route's end waypoint sequence
    route = trip.routes
                .joins(:waypoint_end)
                .where('waypoints.sequence >= ?', sequence)
                .order('waypoints.sequence ASC')
                .first

    sequence -= 1 if route && sequence == route.waypoint_end.sequence

    create_attrs = {
      trip_id: trip_id,
      sequence: sequence,
      waypoint_type: waypoint_type,
      delay: delay,
      name: osm_poi.name || osm_poi.metadata.dig('all_tags', 'note'),
      lonlat: osm_poi.lonlat,
      osm_poi_id: osm_poi.old_id
    }

    create_attrs[:toll] = osm_poi.toll_amount if osm_poi.toll_amount

    create(create_attrs)
  rescue ActiveRecord::RecordNotUnique
    # Race condition fallback — another POI was inserted concurrently,
    # retry with the next available sequence
    sequence += 1
    retry
  end

  def latlon=(coordinates)
    latlon = coordinates.split(',')
    send(:lonlat=, GEO_FACTORY.point(latlon[1], latlon[0]))
  end

  def latlon
    return nil unless lonlat

    "#{lonlat.y}, #{lonlat.x}"
  end

  # Delegates to Waypoints::BoundaryAssigner — see app/services/waypoints/boundary_assigner.rb
  def self.find_boundary(level)
    Waypoints::BoundaryAssigner.assign_missing(levels: [level])
  end

  def self.calculate_sequence_for_position(trip, route, lat, lon)
    # Get the start and end waypoints for this route
    waypoint_start = route.waypoint_start
    waypoint_end = route.waypoint_end

    return 1 unless waypoint_start && waypoint_end

    # Find closest point on route and its fraction (0.0 to 1.0)
    point_info = route.closest_point_info(lat, lon)
    fraction = point_info[:fraction]

    # Get all waypoints between start and end, ordered by sequence
    existing_waypoints = trip.waypoints
                             .where('sequence > ? AND sequence < ?', waypoint_start.sequence, waypoint_end.sequence)
                             .order(:sequence)

    # If no waypoints exist between start and end, use fraction to calculate
    if existing_waypoints.empty?
      # Calculate sequence as fraction between start and end
      return (waypoint_start.sequence + (fraction * (waypoint_end.sequence - waypoint_start.sequence))).round
    end

    # Find where this waypoint should be inserted based on its fraction
    # Compare with fractions of existing waypoints
    prev_waypoint = waypoint_start
    prev_fraction = 0.0

    existing_waypoints.each do |wp|
      next unless wp.lonlat

      wp_point_info = route.closest_point_info(wp.lonlat.y, wp.lonlat.x)
      wp_fraction = wp_point_info[:fraction]

      # If new waypoint comes before this existing waypoint
      if fraction < wp_fraction
        # Calculate sequence between prev_waypoint and wp based on fraction
        fraction_range = wp_fraction - prev_fraction
        fraction_position = fraction - prev_fraction
        fraction_percent = fraction_position / fraction_range

        sequence_range = wp.sequence - prev_waypoint.sequence
        new_sequence = prev_waypoint.sequence + (fraction_percent * sequence_range).round

        new_sequence += 1 if new_sequence == prev_waypoint.sequence
        new_sequence -= 1 if new_sequence == wp.sequence
        return new_sequence
      end

      # Update for next iteration
      prev_waypoint = wp
      prev_fraction = wp_fraction
    end

    # If we get here, waypoint comes after all existing waypoints
    # Calculate sequence between last waypoint and end
    fraction_range = 1.0 - prev_fraction
    fraction_position = fraction - prev_fraction
    fraction_percent = fraction_position / fraction_range

    sequence_range = waypoint_end.sequence - prev_waypoint.sequence
    prev_waypoint.sequence + (fraction_percent * sequence_range).round
  end

  # Triggers boundary assignment after the waypoint is saved.
  # Kept thin — all logic lives in Waypoints::BoundaryAssigner.
  def assign_boundaries
    Waypoints::BoundaryAssigner.new(self).assign
  end

  def recalculate_affected_route
    CalculateRouteJob.perform_later(route.id) if route
  end
end
