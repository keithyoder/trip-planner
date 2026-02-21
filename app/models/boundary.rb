# frozen_string_literal: true

# == Schema Information
#
# Table name: boundaries
#
#  id            :bigint           not null, primary key
#  name          :string
#  level         :integer
#  geom          :geography        multipolygon, 4326
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  hierarchy     :ltree
#  admin_point   :geography        point, 4326
#  osm_id        :integer
#  admin_node_id :bigint
#  timezone      :string
#
class Boundary < ActiveRecord::Base
  has_and_belongs_to_many :waypoints
  has_many :holidays, dependent: :destroy

  scope :without_geom, -> { select(:id, :name, :level, :timezone, :hierarchy, :osm_id, :admin_node_id, :admin_point) }

  scope :waypoint, lambda { |waypoint, level|
    where("ST_Within(ST_GeomFromText('#{waypoint.lonlat}', 4326), geom::geometry) AND level = #{level}")
  }

  scope :containing_point, lambda { |lat, lon|
    where('ST_Within(ST_SetSRID(ST_MakePoint(?, ?), 4326), geom::geometry)', lon, lat)
  }

  scope :intersecting_with_route, lambda { |route_id|
    joins('JOIN routes ON ST_Intersects(boundaries.geom::geometry, routes.geom::geometry)')
      .where(routes: { id: route_id })
      .select(<<~SQL)
          boundaries.id, name, level, hierarchy, osm_id,
          ST_Length(
            ST_Intersection(boundaries.geom::geometry, routes.geom::geometry)::geography
          ) AS intersection_distance,
        ST_LineLocatePoint(
          routes.geom::geometry,
          ST_StartPoint(ST_Intersection(boundaries.geom::geometry, routes.geom::geometry))
        ) AS intersection_order
      SQL
      .order('intersection_order ASC', 'boundaries.level ASC')
  }

  attribute :intersection_distance, :distance, units: :meters

  def import_boundaries(level)
    osm = OsmBoundary.new
    osm.fetch_and_import(osm_id, level: level, hierarchy_prefix: hierarchy)
  end

  def self.load_geojson(file_name)
    geom = RGeo::GeoJSON.decode(File.read(file_name))
    geom.each do |g|
      boundary = Boundary.find_or_initialize_by(osm_id: g['osm_id'])
      boundary.update!(
        name: g['name'],
        hierarchy: "South_America.Peru.#{(g['name_en'] || g['name']).parameterize.underscore}",
        level: g['admin_level'],
        admin_node_id: g['admin_centre_node_id'],
        admin_point: RGeo::Geographic.spherical_factory(srid: 4326).point(
          g['admin_centre_node_lng'], g['admin_centre_node_lat']
        ),
        geom: g.geometry
      )
    end
  end

  def descendants_at_level(level, include_self: false)
    query = Boundary.where('hierarchy <@ ?', hierarchy)
                    .where(level: level)

    query = query.where.not(id: id) unless include_self
    query
  end

  # Helper method to get all holidays for a specific year, sorted by date
  # Includes holidays from this boundary and all parent boundaries
  def holidays_for_year(year)
    all_boundary_holidays.map do |holiday|
      {
        holiday: holiday,
        date: holiday.date_for_year(year),
        boundary: {
          name: holiday.boundary_name,
          level: holiday.level
        }
      }
    end.sort_by { |h| h[:date] }
  end

  # Check if a specific date is a holiday in this boundary or any parent boundary
  def holiday_on?(date)
    all_boundary_holidays.any? { |holiday| holiday.occurs_on?(date) }
  end

  # Get the holiday(s) that occur on a specific date (including parent boundaries)
  def holidays_on(date)
    all_boundary_holidays.select { |holiday| holiday.occurs_on?(date) }
  end

  private

  # Get all holidays from this boundary and all parent boundaries using ltree
  def all_boundary_holidays
    Holiday.joins('INNER JOIN boundaries ON boundaries.id = holidays.boundary_id')
           .select('holidays.*')
           .select('boundaries.name as boundary_name')
           .select('boundaries.level as level')
           .where('boundaries.hierarchy @> ?', hierarchy)
  end
end
