# frozen_string_literal: true

class Route < ApplicationRecord
  GEO_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

  belongs_to :trip
  has_one :route_sequence
  has_many :elevations, class_name: 'RouteElevation'
  belongs_to :waypoint_start, class_name: 'Waypoint'
  belongs_to :waypoint_end, class_name: 'Waypoint'

  scope :bounding_box, -> {
    select("ST_Envelope(geom::geometry) AS bounding_box, *")
  }

  scope :distance_to_point, ->(lat, lng) {
    select(["ST_Distance(geom, ST_Point(#{lng}, #{lat})) as distance"])
  }



  def waypoints
    trip.waypoints.where(sequence: [waypoint_start.sequence..waypoint_end.sequence]).order(:sequence)
  end

  def waypoints_coordinates
    waypoints.map { |wp| [wp.lonlat.x, wp.lonlat.y] }
  end

  #def start_time
  #  puts self[:start_time].presence
  #  puts ActiveSupport::Duration.parse('PT9H') 
  #  (Date.today + (self[:start_time].presence || ActiveSupport::Duration.parse('PT9H'))).to_time
  #end
  #
  def google_maps_url
    origin = "origin=#{waypoint_start.lonlat.latitude},#{waypoint_start.lonlat.longitude}"
    destination = "destination=#{waypoint_end.lonlat.latitude},#{waypoint_end.lonlat.longitude}"
    pois = "waypoints="+waypoints.to_a[1..-2].map { |w| "#{w.lonlat.latitude},#{w.lonlat.longitude}" }.join("|")
    parameters = [origin, destination, pois].join('&')
    "https://www.google.com/maps/dir/?api=1&#{parameters}"
  end

  
  def calculate_route
    response = ors.post(
      "/v2/directions/#{profile}/geojson",
      {
        "elevation": true,
        "extra_info": ["tollways","surface", "waycategory", "waytype"],
        "coordinates": waypoints_coordinates
      }
    )
    puts response[:features].first[:properties][:extras]
    update(
      segments: response[:features].first[:properties][:segments],
      surfaces: response[:features].first[:properties][:extras][:surface],
    )

    Route.connection.exec_update(
      Route.sanitize_sql(
        [
          'update routes set geom = ST_Force4D(ST_GeomFromGeoJSON(:geom)) where id = :id and trip_id = :trip_id',
          {
            id: id,
            trip_id: trip_id,
            geom: response[:features].first[:geometry].to_json
          }
        ]
      )
    )
  end

  def import_duration
    line = RGeo::GeoJSON.encode(geom)
    wp = waypoints.to_a
    duration = 0
    segments.each do |segment|
      waypoint = wp.shift
      puts waypoint.inspect
      duration += waypoint.delay || 0
      segment['steps'].each do |step|
        velocity = step['distance'] / step['duration']
        #duration = line['coordinates'][step['way_points'].first][3]
        # skip one-point segments
        next unless step['way_points'].first + 1 <= step['way_points'].last

        (step['way_points'].first + 1..step['way_points'].last).each do |waypoint|
          distance = distance_between_points(line['coordinates'][waypoint], line['coordinates'][waypoint - 1])
          duration += (distance / velocity) unless velocity.nan?
          line['coordinates'][waypoint][3] = duration
        end
      end
    end

    coords = line['coordinates'].map { |c| c.join(' ') }
    linestring = "LINESTRING ZM (#{coords.join(',')})"
    # update(geom: linestring)
    Route.connection.exec_update(
      Route.sanitize_sql(
        [
          'update routes set geom = ST_GeomFromText(:geom)::geography where id = :id',
          {
            id: id,
            geom: linestring
          }
        ]
      )
    )
  end

  def import_elevation
    sql = if geom.num_points > 1999
            Route.sanitize_sql([
              'UPDATE routes
                SET geom = ST_Force4D(ST_MakeLine(
                  ST_GeomFromGeoJSON(:geom1),
                  ST_GeomFromGeoJSON(:geom2)
                )) where id = :id',
              {
                id: id,
                geom1: ors_elevation(subsegment(1)),
                geom2: ors_elevation(subsegment(2))
              }
            ])
          else
            Route.sanitize_sql(
              [
                'update routes set geom = ST_Force4D(ST_GeomFromGeoJSON(:geom)) where id = :id',
                {
                  id: id,
                  geom: ors_elevation(geom)
                }
              ]
            )
          end

    Route.connection.exec_update(sql)
  end

  def subsegment(segment)
    segment_sql = Arel.sql(Route.sanitize_sql(["
      ST_GeometryN(
        ST_Split(
          geom::geometry,
          ST_GeometryN(ST_Points(geom::geometry), ST_NPoints(geom::geometry)/2)
        ), ?
      )::geography as geom
      ", segment]))
    @trip.routes.where(id: id).pluck(segment_sql).first
  end

  def points
    joins_sql = "
      JOIN (
        SELECT id as route_id, ST_DumpPoints(geom::geometry) AS dp FROM routes) as points
      ON routes.id = points.route_id
    "
    select_sql = "
      routes.id, (dp).geom,
      ST_Length(ST_GeometryN(ST_Split(routes.geom::geometry, (dp).geom), 1)::geography) as segment_length
    "
    Route.joins(joins_sql).where(id: id).select(Arel.sql(select_sql))
  end

  def self.find_by_waypoint(waypoint)
    Route.joins([:waypoint_start, :waypoint_end]).where("#{waypoint.sequence} between waypoints.sequence and waypoint_ends_routes.sequence").first
  end

  private

  def ors
    OpenRouteService.new('5b3ce3597851110001cf62480c927401fb274f2db86c351d93c998ad')
  end

  def ors_elevation(line)
    geojson = RGeo::GeoJSON.encode(line)
    # remove the m-value from points
    geojson['coordinates'].each { |c| c.delete_at(2) }
    body = {
      format_in: 'geojson',
      geometry: geojson
    }
    response = ors.post('/elevation/line', body)
    puts (response[:geometry][:coordinates].count)
    response[:geometry].to_json
  end

  def distance_between_points(pt1, pt2)
    GEO_FACTORY.point(pt1[0], pt1[1]).distance(GEO_FACTORY.point(pt2[0], pt2[1]))
  end
end
