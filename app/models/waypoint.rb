# frozen_string_literal: true

class Waypoint < ApplicationRecord
  belongs_to :trip
  has_and_belongs_to_many :boundaries
  has_one :osm_poi
  has_one :waypoint_distance, foreign_key: :id

  attribute :distance, :distance

  GEO_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

  COUNTRY_CURRENCY = {
    Brasil: :brl,
    Uruguay: :uyu,
    Argentina: :ars,
    Chile: :clp,
    Bolivia: :bob,
    Peru: :pen
  }

  enum waypoint_type: {
    overnight: 1,
    lunch: 2,
    ferry_boarding: 3,
    ferry_disembarkment: 4,
    toll_booth: 5,
    border_crossing: 6,
    gas_station: 7,
    attraction: 8, 
    routing: 9,
  }

  geocoded_by :address do |record, results|
    result = results.first

    record.address = result.address # Store the address used for geocoding
    record.lonlat = GEO_FACTORY.point(result.longitude, result.latitude)
  end

  scope :no_level, ->(level) {
    where("id not in (SELECT waypoint_id FROM boundaries_waypoints JOIN boundaries ON boundaries_waypoints.boundary_id = boundaries.id WHERE level = #{level})")
  }

  def route_sequence
    Route.find_by_waypoint(self).route_sequence
  end

  def country
    @country ||= boundaries.where(level: 2).pluck(:name).join(' ')
  end

  def currency
    COUNTRY_CURRENCY[country.to_sym]
  end

  def state
    boundaries.where(level: 4).pluck(:name).join(' ')
  end

  def location
    boundaries.order(:level).pluck(:name).join(', ')
  end

  def timezone
    # Find the boundary highest (more precise) level with a timezone
    boundaries.where.not(timezone: nil).order(level: :desc).pluck(:timezone).first
  end

  def solar_position(date = Date.today)
    @solar_position ||= SolarPosition.new(date, lonlat, timezone)
  end

  def copy_from_osm(osm_poi_id)
    osm_poi = OsmPoi.find(osm_poi_id)
    puts osm_poi.to_json
    case osm_poi.poi_type
    when 'fuel'
      waypoint_type = :gas_station
      delay = 900
    when 'border_crossing'
      waypoint_type = :border_crossing
      delay = 1800
    when 'toll'
      waypoint_type = :toll_booth
      delay = 0
    end
    update!(
      waypoint_type: waypoint_type,
      delay: delay,
      name: osm_poi.name,
      lonlat: osm_poi.geom,
      osm_poi_id: osm_poi.id
    )    
  end

  def self.copy_from_osm(osm_poi_id, sequence)
    osm_poi = OsmPoi.find(osm_poi_id)
    puts osm_poi.to_json
    case osm_poi.poi_type
    when 'fuel'
      waypoint_type = :gas_station
      delay = 900
    when 'border'
      waypoint_type = :border_crossing
      delay = 1800
    when 'toll'
      waypoint_type = :toll_booth
      delay = 0
    end
    Waypoint.create(
      sequence: sequence,
      waypoint_type: waypoint_type,
      delay: delay,
      name: osm_poi.name,
      lonlat: osm_poi.geom,
      osm_poi_id: osm_poi.id
    )
  end

  def latlon=(coordinates)
    latlon = coordinates.split(',')
    send(:lonlat=, GEO_FACTORY.point(latlon[1], latlon[0]))
  end

  def self.find_boundary(level)
    Waypoint.no_level(level).each do |w| 
      boundary = Boundary.select(:id).waypoint(w, level).first
      w.boundaries << boundary if boundary.present?
    end
  end
end
