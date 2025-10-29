# frozen_string_literal: true

class Boundary < ActiveRecord::Base
  has_and_belongs_to_many :waypoints

  scope :waypoint, lambda { |waypoint, level|
    where("ST_Within(ST_GeomFromText('#{waypoint.lonlat}', 4326), geom::geometry) AND level = #{level}")
  }

  scope :containing_point, lambda { |lat, lon|
    where('ST_Within(ST_SetSRID(ST_MakePoint(?, ?), 4326), geom::geometry)', lon, lat)
  }

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
end
