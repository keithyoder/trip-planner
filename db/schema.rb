# frozen_string_literal: true

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 20_260_223_133_536) do
  # These are extensions that must be enabled in order to support this database
  enable_extension 'ltree'
  enable_extension 'plpgsql'
  enable_extension 'postgis'

  create_table 'boundaries', force: :cascade do |t|
    t.string 'name'
    t.integer 'level'
    t.geography 'geom', limit: { srid: 4326, type: 'multi_polygon', geographic: true }
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.ltree 'hierarchy'
    t.geography 'admin_point', limit: { srid: 4326, type: 'st_point', geographic: true }
    t.integer 'osm_id'
    t.bigint 'admin_node_id'
    t.string 'timezone'
    t.index ['geom'], name: 'index_boundaries_on_geom', using: :gist
    t.index ['level'], name: 'index_boundaries_on_level'
    t.index ['osm_id'], name: 'index_boundaries_on_osm_id', unique: true
  end

  create_table 'boundaries_waypoints', id: false, force: :cascade do |t|
    t.bigint 'waypoint_id', null: false
    t.bigint 'boundary_id', null: false
    t.index %w[boundary_id waypoint_id], name: 'index_boundaries_waypoints_on_boundary_and_waypoint'
    t.index %w[waypoint_id boundary_id], name: 'index_boundaries_waypoints_on_waypoint_and_boundary'
  end

  create_table 'holidays', force: :cascade do |t|
    t.bigint 'boundary_id', null: false
    t.string 'name', null: false
    t.integer 'month'
    t.integer 'day'
    t.integer 'calculation_type', default: 0, null: false
    t.integer 'offset_days', default: 0
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index %w[boundary_id name], name: 'index_holidays_on_boundary_id_and_name'
    t.index ['boundary_id'], name: 'index_holidays_on_boundary_id'
    t.index ['calculation_type'], name: 'index_holidays_on_calculation_type'
  end

  create_table 'osm_pois', primary_key: 'old_id', id: :bigint, default: lambda {
    "nextval('osm_pois_id_seq'::regclass)"
  }, force: :cascade do |t|
    t.string 'name'
    t.integer 'poi_type'
    t.string 'city'
    t.string 'country'
    t.string 'district'
    t.string 'housenumber'
    t.string 'milestone'
    t.string 'postcode'
    t.string 'province'
    t.string 'state'
    t.string 'street'
    t.geography 'geom', limit: { srid: 4326, type: 'st_point', geographic: true }
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'osm_type', default: 'node', null: false
    t.string 'osm_id', null: false
    t.jsonb 'metadata', default: {}
    t.index ['metadata'], name: 'index_osm_pois_on_metadata', using: :gin
    t.index ['osm_id'], name: 'index_osm_pois_on_osm_id', unique: true
  end

  create_table 'routes', force: :cascade do |t|
    t.bigint 'waypoint_start_id', null: false
    t.bigint 'waypoint_end_id', null: false
    t.jsonb 'segments'
    t.geography 'geom', limit: { srid: 4326, type: 'line_string', has_z: true, has_m: true, geographic: true }
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.interval 'start_time'
    t.bigint 'trip_id'
    t.string 'profile', default: 'driving-car', null: false
    t.jsonb 'surfaces', default: {}
    t.index ['trip_id'], name: 'index_routes_on_trip_id'
    t.index ['waypoint_end_id'], name: 'index_routes_on_waypoint_end_id'
    t.index ['waypoint_start_id'], name: 'index_routes_on_waypoint_start_id'
  end

  create_table 'telemetry_logs', force: :cascade do |t|
    t.string 'mongo_id', null: false
    t.datetime 'timestamp', null: false
    t.jsonb 'data', default: {}, null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['data'], name: 'index_telemetry_logs_on_data', using: :gin
    t.index ['mongo_id'], name: 'index_telemetry_logs_on_mongo_id', unique: true
    t.index ['timestamp'], name: 'index_telemetry_logs_on_timestamp'
  end

  create_table 'trip_logs', force: :cascade do |t|
    t.string 'name'
    t.datetime 'start_time', null: false
    t.datetime 'end_time', null: false
    t.decimal 'max_speed', precision: 8, scale: 3
    t.decimal 'avg_speed', precision: 8, scale: 3
    t.geography 'geom', limit: { srid: 4326, type: 'geometry', geographic: true }
    t.jsonb 'data', default: {}, null: false
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['geom'], name: 'index_trip_logs_on_geom', using: :gist
    t.index ['start_time'], name: 'index_trip_logs_on_start_time', unique: true
  end

  create_table 'trips', force: :cascade do |t|
    t.string 'name'
    t.date 'start_on'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.string 'vehicle_description'
    t.decimal 'fuel_consumption_l_per_100km', precision: 4, scale: 2
  end

  create_table 'users', force: :cascade do |t|
    t.string 'email', default: '', null: false
    t.string 'provider'
    t.string 'uid'
    t.string 'name'
    t.string 'avatar_url'
    t.integer 'sign_in_count', default: 0, null: false
    t.datetime 'current_sign_in_at'
    t.datetime 'last_sign_in_at'
    t.string 'current_sign_in_ip'
    t.string 'last_sign_in_ip'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['email'], name: 'index_users_on_email', unique: true
    t.index %w[provider uid], name: 'index_users_on_provider_and_uid', unique: true
  end

  create_table 'waypoints', force: :cascade do |t|
    t.string 'name'
    t.string 'address'
    t.integer 'sequence'
    t.geography 'lonlat', limit: { srid: 4326, type: 'st_point', geographic: true }
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.integer 'waypoint_type'
    t.decimal 'toll'
    t.integer 'delay'
    t.bigint 'osm_poi_id'
    t.bigint 'trip_id'
    t.string 'osm_poi_osm_id'
    t.index ['osm_poi_id'], name: 'index_waypoints_on_osm_poi_id'
    t.index ['osm_poi_osm_id'], name: 'index_waypoints_on_osm_poi_osm_id'
    t.index %w[trip_id sequence], name: 'index_waypoints_on_trip_id_and_sequence', unique: true
    t.index ['trip_id'], name: 'index_waypoints_on_trip_id'
  end

  add_foreign_key 'holidays', 'boundaries'
  add_foreign_key 'routes', 'trips'
  add_foreign_key 'routes', 'waypoints', column: 'waypoint_end_id'
  add_foreign_key 'routes', 'waypoints', column: 'waypoint_start_id'
  add_foreign_key 'waypoints', 'trips'

  create_view 'route_sequences', sql_definition: <<-SQL
      WITH r1 AS (
           SELECT routes.id AS route_id,
              routes.trip_id,
              w1.sequence,
              (((w1.name)::text || ' - '::text) || (w2.name)::text) AS route_name,
              ((sum(w3.delay) || ' seconds'::text))::interval AS stopped_time,
              st_length(routes.geom) AS distance,
              (((st_m(st_endpoint((routes.geom)::geometry)) - st_m(st_startpoint((routes.geom)::geometry))) || ' second'::text))::interval AS duration
             FROM routes,
              waypoints w1,
              waypoints w2,
              waypoints w3
            WHERE ((routes.waypoint_start_id = w1.id) AND (routes.waypoint_end_id = w2.id) AND (routes.trip_id = w1.trip_id) AND (routes.trip_id = w2.trip_id) AND (routes.trip_id = w3.trip_id) AND ((w3.sequence >= w1.sequence) AND (w3.sequence <= w2.sequence)))
            GROUP BY routes.id, w1.sequence, w1.name, w2.name
          ), r2 AS (
           SELECT routes.id,
              routes.trip_id,
              routes.start_time,
              waypoints.sequence
             FROM routes,
              waypoints
            WHERE (routes.waypoint_start_id = waypoints.id)
          )
   SELECT r1.route_id,
      r1.trip_id,
      r1.sequence,
      r1.route_name,
      r1.stopped_time,
      r1.distance,
      r1.duration,
      sum(r2.start_time) AS start_time_sequence
     FROM (r1
       LEFT JOIN r2 ON (((r2.sequence <= r1.sequence) AND (r2.trip_id = r1.trip_id))))
    GROUP BY r1.trip_id, r1.route_id, r1.sequence, r1.route_name, r1.stopped_time, r1.distance, r1.duration
    ORDER BY r1.trip_id;
  SQL
  create_view 'route_tracks', sql_definition: <<-SQL
      SELECT (st_union((geom)::geometry))::geography AS track,
      st_length((st_union((geom)::geometry))::geography) AS distance
     FROM routes;
  SQL
  create_view 'trip_tracks', sql_definition: <<-SQL
      SELECT trip_id,
      (st_union((geom)::geometry))::geography AS geom,
      st_length((st_union((geom)::geometry))::geography) AS distance
     FROM routes
    GROUP BY trip_id;
  SQL
  create_view 'waypoint_distances', sql_definition: <<-SQL
      WITH wp AS (
           SELECT wp.id,
              wp.name,
              wp.address,
              wp.sequence,
              wp.lonlat,
              wp.created_at,
              wp.updated_at,
              wp.waypoint_type,
              wp.toll,
              wp.delay,
              wp.osm_poi_id,
              wp.trip_id,
              routes.id AS route_id,
              row_number() OVER (PARTITION BY routes.id ORDER BY wp.sequence) AS row_number
             FROM routes,
              waypoints wp,
              waypoints way_start,
              waypoints way_end
            WHERE ((routes.waypoint_start_id = way_start.id) AND (routes.waypoint_end_id = way_end.id) AND (routes.trip_id = wp.trip_id) AND (routes.trip_id = way_start.trip_id) AND (routes.trip_id = way_end.trip_id) AND ((wp.sequence >= way_start.sequence) AND (wp.sequence <= way_end.sequence)))
            ORDER BY wp.sequence, routes.id
          ), route_points AS (
           SELECT routes.trip_id,
              wp.route_id,
              st_collect(array_agg(st_3dclosestpoint((wp.lonlat)::geometry, (routes.geom)::geometry) ORDER BY wp.sequence)) AS points,
              st_snap((routes.geom)::geometry, st_collect(array_agg(st_3dclosestpoint((wp.lonlat)::geometry, (routes.geom)::geometry) ORDER BY wp.sequence)), (0.001)::double precision) AS snapped_track
             FROM wp,
              routes
            WHERE ((wp.route_id = routes.id) AND (routes.trip_id = wp.trip_id))
            GROUP BY routes.trip_id, wp.route_id, routes.geom
          ), route_segments AS (
           SELECT route_points.trip_id,
              route_points.route_id,
              route_points.points,
              route_points.snapped_track,
              st_dump(st_split(route_points.snapped_track, route_points.points)) AS segment
             FROM route_points
          ), waypoint_distances AS (
           SELECT route_segments.trip_id,
              closest_points.id,
              closest_points.sequence,
              route_segments.route_id,
              st_length(((route_segments.segment).geom)::geography) AS distance
             FROM (route_segments
               CROSS JOIN LATERAL ( SELECT wp.id,
                      wp.row_number,
                      wp.sequence
                     FROM wp
                    ORDER BY (wp.lonlat <-> (st_endpoint((route_segments.segment).geom))::geography)
                   LIMIT 1) closest_points)
          )
   SELECT waypoints.id,
      waypoints.name,
      waypoints.address,
      waypoints.sequence,
      waypoints.lonlat,
      waypoints.created_at,
      waypoints.updated_at,
      waypoints.waypoint_type,
      waypoints.toll,
      waypoints.delay,
      waypoints.osm_poi_id,
      waypoints.trip_id,
      sum(COALESCE(waypoint_distances.distance, (0)::double precision)) FILTER (WHERE (waypoints.id = waypoint_distances.id)) AS segment_distance,
      sum(COALESCE(waypoint_distances.distance, (0)::double precision)) AS trip_distance
     FROM (waypoints
       LEFT JOIN waypoint_distances ON (((waypoints.sequence >= waypoint_distances.sequence) AND (waypoints.trip_id = waypoint_distances.trip_id))))
    GROUP BY waypoints.id
    ORDER BY waypoints.sequence;
  SQL
end
