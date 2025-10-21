WITH wp AS (
    SELECT
        wp.*,
        routes.id AS route_id,
        ROW_NUMBER() OVER (PARTITION BY routes.id ORDER BY wp.sequence)
    FROM routes,
    waypoints wp,
    waypoints way_start,
    waypoints way_end
    WHERE routes.waypoint_start_id = way_start.id
        AND routes.waypoint_end_id = way_end.id
        AND wp.sequence BETWEEN way_start.sequence AND way_end.sequence
    ORDER BY
        wp.sequence,
        routes.id
),
route_points AS (
    SELECT
        route_id,
        ST_Collect(array_agg(ST_3DClosestPoint(lonlat::geometry, geom::geometry)
            ORDER BY wp.sequence)) AS points,
        st_snap(geom::geometry, ST_Collect(array_agg(ST_3DClosestPoint(lonlat::geometry, geom::geometry)
            ORDER BY wp.sequence)), 0.001) AS snapped_track
FROM
    wp,
    routes
    WHERE
        route_id = routes.id
    GROUP BY
        route_id,
        geom
),
route_segments AS (
    SELECT
        route_id,
        points,
        snapped_track,
        ST_Dump(ST_Split(snapped_track, points)) AS segment
    FROM
        route_points
),
waypoint_distances AS (
    SELECT
        closest_points.id,
        closest_points.sequence,
        route_segments.route_id,
        ST_Length((route_segments.segment).geom::geography) AS distance
    FROM
        route_segments
        CROSS JOIN LATERAL (
            SELECT
                id,
                row_number,
                SEQUENCE
            FROM
                wp
            ORDER BY
                lonlat <-> ST_EndPoint((segment).geom)
            LIMIT 1) AS closest_points
)
SELECT
    waypoints.*,
    sum(coalesce(waypoint_distances.distance, 0)) FILTER (WHERE waypoints.id = waypoint_distances.id) AS segment_distance,
    sum(coalesce(waypoint_distances.distance, 0)) AS trip_distance
FROM
    waypoints
    LEFT JOIN waypoint_distances ON waypoints.sequence >= waypoint_distances.sequence
GROUP BY
    waypoints.id
ORDER BY
    waypoints.sequence
