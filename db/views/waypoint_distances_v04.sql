WITH route_waypoints AS (
  SELECT
    wp.id                                                              AS waypoint_id,
    wp.sequence,
    wp.trip_id,
    r.id                                                               AS route_id,
    ST_Length(r.geom::geography)                                       AS route_length,
    ST_LineLocatePoint(
      ST_Force2D(r.geom::geometry),
      ST_Force2D(wp.lonlat::geometry)
    )                                                                  AS fraction
  FROM routes r
  JOIN waypoints ws ON ws.id = r.waypoint_start_id
  JOIN waypoints we ON we.id = r.waypoint_end_id
  JOIN waypoints wp ON wp.trip_id = r.trip_id
                    AND wp.sequence BETWEEN ws.sequence AND we.sequence
),
leg_distances AS (
  SELECT
    waypoint_id,
    sequence,
    trip_id,
    route_id,
    route_length * fraction AS distance_along_route,
    (route_length * fraction)
      - LAG(route_length * fraction, 1, 0.0)
          OVER (PARTITION BY route_id ORDER BY sequence) AS segment_distance
  FROM route_waypoints
),
trip_totals AS (
  SELECT
    waypoint_id,
    trip_id,
    sequence,
    segment_distance,
    SUM(segment_distance) OVER (
      PARTITION BY trip_id
      ORDER BY sequence
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS trip_distance
  FROM leg_distances
)
SELECT
  w.id,
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
  COALESCE(t.segment_distance, 0) AS segment_distance,
  COALESCE(t.trip_distance,    0) AS trip_distance
FROM waypoints w
LEFT JOIN trip_totals t ON t.waypoint_id = w.id;