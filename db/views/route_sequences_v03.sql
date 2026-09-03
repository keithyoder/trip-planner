WITH RECURSIVE r1 AS (
    SELECT
        routes.id as route_id,
        routes.trip_id,
        w1.sequence,
        w1.name || ' - ' || w2.name AS route_name,
        (sum(w3.delay) || ' seconds')::interval AS stopped_time,
        ST_Length (geom) AS distance,
        (ST_M (ST_EndPoint (geom::geometry)) - ST_M (ST_StartPoint (geom::geometry)) || ' second')::interval AS duration
    FROM
        routes,
        waypoints w1,
        waypoints w2,
        waypoints w3
    WHERE
        routes.waypoint_start_id = w1.id
        AND routes.waypoint_end_id = w2.id
        AND routes.trip_id = w1.trip_id
        AND routes.trip_id = w2.trip_id
        AND routes.trip_id = w3.trip_id
        AND w3.sequence BETWEEN w1.sequence AND w2.sequence
    GROUP BY
        routes.id,
        w1.sequence,
        w1.name,
        w2.name
),
routes_ordered AS (
    SELECT
        routes.id AS route_id,
        routes.trip_id,
        routes.start_time,
        waypoints.sequence,
        ROW_NUMBER() OVER (PARTITION BY routes.trip_id ORDER BY waypoints.sequence) AS rn
    FROM
        routes
        JOIN waypoints ON routes.waypoint_start_id = waypoints.id
),
cum AS (
    -- First route of the trip: no previous route to anchor to, so
    -- start_time is already relative to trip start.
    SELECT
        route_id, trip_id, sequence, rn,
        start_time AS start_time_sequence
    FROM routes_ordered
    WHERE rn = 1

    UNION ALL

    -- Every later route: anchor to midnight of the *previous* route's
    -- cumulative start (floor to whole days), then add this route's own
    -- (relative-to-that-midnight) start_time.
    SELECT
        ro.route_id, ro.trip_id, ro.sequence, ro.rn,
        make_interval(
          days => floor(extract(epoch FROM cum.start_time_sequence) / 86400)::int
        ) + ro.start_time AS start_time_sequence
    FROM
        routes_ordered ro
        JOIN cum ON ro.trip_id = cum.trip_id AND ro.rn = cum.rn + 1
)
SELECT
    r1.*,
    cum.start_time_sequence
FROM
    r1
    JOIN cum ON cum.route_id = r1.route_id
ORDER BY
    r1.sequence