WITH r1 AS (
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
r2 AS (
    SELECT
        routes.id,
        routes.trip_id,
        routes.start_time,
        waypoints.sequence
    FROM
        routes,
        waypoints
    WHERE
        routes.waypoint_start_id = waypoints.id
)
SELECT
    r1.*,
    sum(r2.start_time) AS start_time_sequence
FROM
    r1
    LEFT JOIN r2 ON r2.sequence <= r1.sequence AND r2.trip_id = r1.trip_id
GROUP BY
    r1.trip_id,
    r1.route_id,
    r1.sequence,
    r1.route_name,
    r1.stopped_time,
    r1.distance,
    r1.duration
ORDER BY
    2
