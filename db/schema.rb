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

ActiveRecord::Schema[7.2].define(version: 2026_11_22_230000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "ltree"
  enable_extension "plpgsql"
  enable_extension "postgis"

  create_table "boundaries", force: :cascade do |t|
    t.string "name"
    t.integer "level"
    t.geography "geom", limit: {srid: 4326, type: "multi_polygon", geographic: true}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.ltree "hierarchy"
    t.geography "admin_point", limit: {srid: 4326, type: "st_point", geographic: true}
    t.integer "osm_id"
    t.bigint "admin_node_id"
    t.string "timezone"
    t.index ["geom"], name: "index_boundaries_on_geom", using: :gist
    t.index ["level"], name: "index_boundaries_on_level"
    t.index ["osm_id"], name: "index_boundaries_on_osm_id", unique: true
  end

  create_table "boundaries_waypoints", id: false, force: :cascade do |t|
    t.bigint "waypoint_id", null: false
    t.bigint "boundary_id", null: false
    t.index ["boundary_id", "waypoint_id"], name: "index_boundaries_waypoints_on_boundary_and_waypoint"
    t.index ["waypoint_id", "boundary_id"], name: "index_boundaries_waypoints_on_waypoint_and_boundary"
  end

  create_table "coverage_features", force: :cascade do |t|
    t.bigint "trip_id", null: false
    t.string "provider", null: false
    t.string "layer", null: false
    t.string "source_feature_id"
    t.geometry "geom", limit: {srid: 4326, type: "multi_polygon"}
    t.datetime "fetched_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["geom"], name: "index_coverage_features_on_geom", using: :gist
    t.index ["trip_id", "provider", "layer", "source_feature_id"], name: "index_coverage_features_unique_feature", unique: true
    t.index ["trip_id", "provider", "layer"], name: "index_coverage_features_on_trip_id_and_provider_and_layer"
    t.index ["trip_id"], name: "index_coverage_features_on_trip_id"
  end

  create_table "environment_logs", force: :cascade do |t|
    t.datetime "bucket_start", null: false
    t.datetime "bucket_end", null: false
    t.integer "sample_count", default: 0, null: false
    t.bigint "trip_id"
    t.string "timezone"
    t.decimal "temperature", precision: 5, scale: 2
    t.decimal "humidity", precision: 5, scale: 2
    t.decimal "pressure", precision: 7, scale: 2
    t.decimal "uv_index", precision: 4, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.geometry "location", limit: {srid: 4326, type: "st_point", has_z: true}
    t.index ["bucket_start"], name: "index_environment_logs_on_bucket_start", unique: true
    t.index ["trip_id"], name: "index_environment_logs_on_trip_id"
  end

  create_table "exchange_rates", force: :cascade do |t|
    t.bigint "payment_account_id"
    t.string "from_currency", null: false
    t.string "to_currency", null: false
    t.decimal "rate", precision: 12, scale: 6, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["from_currency", "to_currency", "created_at"], name: "index_exchange_rates_reporting_lookup", where: "(payment_account_id IS NULL)"
    t.index ["payment_account_id", "from_currency", "to_currency", "created_at"], name: "index_exchange_rates_settlement_lookup"
    t.index ["payment_account_id"], name: "index_exchange_rates_on_payment_account_id"
  end

  create_table "expenses", force: :cascade do |t|
    t.bigint "stop_id", null: false
    t.bigint "trip_id"
    t.bigint "payment_account_id"
    t.integer "category", null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "amount_currency", null: false
    t.string "receipt_id"
    t.string "receipt_url"
    t.text "raw_receipt_xml"
    t.jsonb "items", default: [], null: false
    t.jsonb "vendor", default: {}, null: false
    t.integer "settled_amount_cents"
    t.string "settled_currency"
    t.boolean "settled_confirmed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_expenses_on_category"
    t.index ["items"], name: "index_expenses_on_items", using: :gin
    t.index ["payment_account_id"], name: "index_expenses_on_payment_account_id"
    t.index ["receipt_id"], name: "index_expenses_on_receipt_id", unique: true
    t.index ["stop_id"], name: "index_expenses_on_stop_id"
    t.index ["trip_id"], name: "index_expenses_on_trip_id"
    t.index ["vendor"], name: "index_expenses_on_vendor", using: :gin
  end

  create_table "holidays", force: :cascade do |t|
    t.bigint "boundary_id", null: false
    t.string "name", null: false
    t.integer "month"
    t.integer "day"
    t.integer "calculation_type", default: 0, null: false
    t.integer "offset_days", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["boundary_id", "name"], name: "index_holidays_on_boundary_id_and_name"
    t.index ["boundary_id"], name: "index_holidays_on_boundary_id"
    t.index ["calculation_type"], name: "index_holidays_on_calculation_type"
  end

  create_table "osm_pois", primary_key: "old_id", id: :bigint, default: -> { "nextval('osm_pois_id_seq'::regclass)" }, force: :cascade do |t|
    t.string "name"
    t.integer "poi_type"
    t.string "city"
    t.string "country"
    t.string "district"
    t.string "housenumber"
    t.string "milestone"
    t.string "postcode"
    t.string "province"
    t.string "state"
    t.string "street"
    t.geography "geom", limit: {srid: 4326, type: "st_point", geographic: true}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "osm_type", default: "node", null: false
    t.string "osm_id", null: false
    t.jsonb "metadata", default: {}
    t.index ["metadata"], name: "index_osm_pois_on_metadata", using: :gin
    t.index ["osm_id"], name: "index_osm_pois_on_osm_id", unique: true
  end

  create_table "payment_accounts", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", null: false
    t.string "currency", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "routes", force: :cascade do |t|
    t.bigint "waypoint_start_id", null: false
    t.bigint "waypoint_end_id", null: false
    t.jsonb "segments"
    t.geography "geom", limit: {srid: 4326, type: "line_string", has_z: true, has_m: true, geographic: true}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.interval "start_time"
    t.bigint "trip_id"
    t.string "profile", default: "driving-car", null: false
    t.jsonb "surfaces", default: {}
    t.jsonb "day_plan", default: {}
    t.string "day_plan_status", default: "none"
    t.integer "status", default: 0, null: false
    t.index ["trip_id", "status"], name: "index_routes_on_trip_id_status_in_progress", unique: true, where: "(status = 1)"
    t.index ["trip_id"], name: "index_routes_on_trip_id"
    t.index ["waypoint_end_id"], name: "index_routes_on_waypoint_end_id"
    t.index ["waypoint_start_id"], name: "index_routes_on_waypoint_start_id"
  end

  create_table "stops", force: :cascade do |t|
    t.bigint "trip_id"
    t.string "name"
    t.integer "stop_type", null: false
    t.datetime "start_time", null: false
    t.datetime "end_time", null: false
    t.geometry "geom", limit: {srid: 4326, type: "st_point"}, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["trip_id", "start_time"], name: "index_stops_on_trip_id_and_start_time", unique: true
    t.index ["trip_id"], name: "index_stops_on_trip_id"
  end

  create_table "telemetry_logs", force: :cascade do |t|
    t.string "mongo_id", null: false
    t.datetime "timestamp", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data"], name: "index_telemetry_logs_on_data", using: :gin
    t.index ["mongo_id"], name: "index_telemetry_logs_on_mongo_id", unique: true
    t.index ["timestamp"], name: "index_telemetry_logs_on_timestamp"
  end

  create_table "trip_expenses", force: :cascade do |t|
    t.bigint "trip_id", null: false
    t.string "name", null: false
    t.integer "category", default: 0, null: false
    t.decimal "amount", null: false
    t.string "currency", default: "usd", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["trip_id"], name: "index_trip_expenses_on_trip_id"
  end

  create_table "trip_logs", force: :cascade do |t|
    t.string "name"
    t.datetime "start_time", null: false
    t.datetime "end_time", null: false
    t.decimal "max_speed", precision: 8, scale: 3
    t.decimal "avg_speed", precision: 8, scale: 3
    t.geography "geom", limit: {srid: 4326, type: "geometry", geographic: true}
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "trip_id"
    t.index ["geom"], name: "index_trip_logs_on_geom", using: :gist
    t.index ["start_time"], name: "index_trip_logs_on_start_time", unique: true
    t.index ["trip_id"], name: "index_trip_logs_on_trip_id"
  end

  create_table "trips", force: :cascade do |t|
    t.string "name"
    t.date "start_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "vehicle_description"
    t.decimal "fuel_consumption_l_per_100km", precision: 4, scale: 2
    t.integer "status", default: 0, null: false
    t.index ["status"], name: "index_trips_on_status_in_progress", unique: true, where: "(status = 1)"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "provider"
    t.string "uid"
    t.string "name"
    t.string "avatar_url"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  create_table "waypoints", force: :cascade do |t|
    t.string "name"
    t.string "address"
    t.integer "sequence"
    t.geography "lonlat", limit: {srid: 4326, type: "st_point", geographic: true}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "waypoint_type"
    t.decimal "toll"
    t.integer "delay"
    t.bigint "osm_poi_id"
    t.bigint "trip_id"
    t.string "osm_poi_osm_id"
    t.jsonb "notes", default: {}
    t.string "profile", default: "driving-car"
    t.index ["osm_poi_id"], name: "index_waypoints_on_osm_poi_id"
    t.index ["osm_poi_osm_id"], name: "index_waypoints_on_osm_poi_osm_id"
    t.index ["trip_id", "sequence"], name: "index_waypoints_on_trip_id_and_sequence", unique: true
    t.index ["trip_id"], name: "index_waypoints_on_trip_id"
  end

  create_table "weather_estimates", force: :cascade do |t|
    t.decimal "lat", precision: 7, scale: 2, null: false
    t.decimal "lon", precision: 7, scale: 2, null: false
    t.date "planned_date", null: false
    t.float "temp_mean_c"
    t.float "temp_min_c"
    t.float "temp_max_c"
    t.float "temp_min_std"
    t.float "temp_max_std"
    t.float "precipitation_mm"
    t.float "precipitation_std"
    t.integer "precip_probability"
    t.float "windspeed_kmh"
    t.float "windspeed_std"
    t.float "windspeed_max_kmh"
    t.float "windspeed_max_std"
    t.integer "humidity_pct"
    t.integer "weathercode"
    t.integer "cloudcover_pct"
    t.integer "precipitation_hours"
    t.integer "precipitation_probability_max"
    t.string "source", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lat", "lon", "planned_date"], name: "index_weather_estimates_on_location_and_date", unique: true
  end

  add_foreign_key "coverage_features", "trips"
  add_foreign_key "environment_logs", "trips"
  add_foreign_key "exchange_rates", "payment_accounts"
  add_foreign_key "expenses", "payment_accounts"
  add_foreign_key "expenses", "stops"
  add_foreign_key "expenses", "trips"
  add_foreign_key "holidays", "boundaries"
  add_foreign_key "routes", "trips"
  add_foreign_key "routes", "waypoints", column: "waypoint_end_id"
  add_foreign_key "routes", "waypoints", column: "waypoint_start_id"
  add_foreign_key "stops", "trips"
  add_foreign_key "trip_expenses", "trips"
  add_foreign_key "trip_logs", "trips"
  add_foreign_key "waypoints", "trips"

  create_view "route_sequences", sql_definition: <<-SQL
      WITH RECURSIVE r1 AS (
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
          ), routes_ordered AS (
           SELECT routes.id AS route_id,
              routes.trip_id,
              routes.start_time,
              waypoints.sequence,
              row_number() OVER (PARTITION BY routes.trip_id ORDER BY waypoints.sequence) AS rn
             FROM (routes
               JOIN waypoints ON ((routes.waypoint_start_id = waypoints.id)))
          ), cum AS (
           SELECT routes_ordered.route_id,
              routes_ordered.trip_id,
              routes_ordered.sequence,
              routes_ordered.rn,
              routes_ordered.start_time AS start_time_sequence
             FROM routes_ordered
            WHERE (routes_ordered.rn = 1)
          UNION ALL
           SELECT ro.route_id,
              ro.trip_id,
              ro.sequence,
              ro.rn,
              (make_interval(days => (floor((EXTRACT(epoch FROM cum_1.start_time_sequence) / (86400)::numeric)))::integer) + ro.start_time) AS start_time_sequence
             FROM (routes_ordered ro
               JOIN cum cum_1 ON (((ro.trip_id = cum_1.trip_id) AND (ro.rn = (cum_1.rn + 1)))))
          )
   SELECT r1.route_id,
      r1.trip_id,
      r1.sequence,
      r1.route_name,
      r1.stopped_time,
      r1.distance,
      r1.duration,
      cum.start_time_sequence
     FROM (r1
       JOIN cum ON ((cum.route_id = r1.route_id)))
    ORDER BY r1.sequence;
  SQL
  create_view "route_tracks", sql_definition: <<-SQL
      SELECT (st_union((geom)::geometry))::geography AS track,
      st_length((st_union((geom)::geometry))::geography) AS distance
     FROM routes;
  SQL
  create_view "trip_tracks", sql_definition: <<-SQL
      SELECT trip_id,
      (st_union((geom)::geometry))::geography AS geom,
      st_length((st_union((geom)::geometry))::geography) AS distance
     FROM routes
    GROUP BY trip_id;
  SQL
  create_view "waypoint_distances", sql_definition: <<-SQL
      WITH route_waypoints AS (
           SELECT wp.id AS waypoint_id,
              wp.sequence,
              wp.trip_id,
              r.id AS route_id,
              st_length((r.geom)::geography) AS route_length,
              st_linelocatepoint(st_force2d((r.geom)::geometry), st_force2d((wp.lonlat)::geometry)) AS fraction
             FROM (((routes r
               JOIN waypoints ws ON ((ws.id = r.waypoint_start_id)))
               JOIN waypoints we ON ((we.id = r.waypoint_end_id)))
               JOIN waypoints wp ON (((wp.trip_id = r.trip_id) AND ((wp.sequence >= ws.sequence) AND (wp.sequence <= we.sequence)))))
          ), leg_distances AS (
           SELECT route_waypoints.waypoint_id,
              route_waypoints.sequence,
              route_waypoints.trip_id,
              route_waypoints.route_id,
              (route_waypoints.route_length * route_waypoints.fraction) AS distance_along_route,
              ((route_waypoints.route_length * route_waypoints.fraction) - lag((route_waypoints.route_length * route_waypoints.fraction), 1, (0.0)::double precision) OVER (PARTITION BY route_waypoints.route_id ORDER BY route_waypoints.sequence)) AS segment_distance
             FROM route_waypoints
          ), trip_totals AS (
           SELECT leg_distances.waypoint_id,
              leg_distances.trip_id,
              leg_distances.sequence,
              leg_distances.segment_distance,
              sum(leg_distances.segment_distance) OVER (PARTITION BY leg_distances.trip_id ORDER BY leg_distances.sequence ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS trip_distance
             FROM leg_distances
          )
   SELECT w.id,
      w.name,
      w.address,
      w.sequence,
      w.lonlat,
      w.created_at,
      w.updated_at,
      w.waypoint_type,
      w.toll,
      w.delay,
      w.osm_poi_id,
      w.trip_id,
      COALESCE(t.segment_distance, (0)::double precision) AS segment_distance,
      COALESCE(t.trip_distance, (0)::double precision) AS trip_distance
     FROM (waypoints w
       LEFT JOIN trip_totals t ON ((t.waypoint_id = w.id)));
  SQL
end
