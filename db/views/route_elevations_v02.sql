WITH point_data AS (
    SELECT
        routes.id AS route_id,
        (dp).path[1] AS index,
        (dp).geom AS point,  -- Add the actual point geometry
        ST_Y((dp).geom) AS latitude,
        ST_X((dp).geom) AS longitude,
        ST_Z((dp).geom) AS elevation,
        CASE WHEN (dp).path[1] = 1 THEN
            0
        ELSE
            ST_Length(ST_GeometryN(ST_Split(geom::geometry,(dp).geom), 1)::geography)
        END AS distance
    FROM (
        SELECT
            id,
            ST_DumpPoints(geom::geometry) AS dp
        FROM
            routes
    ) AS route_points,
    routes
    WHERE
        route_points.id = routes.id
),
bucketed AS (
    SELECT
        route_id,
        index,
        latitude,
        longitude,
        elevation,
        distance,
        FLOOR(distance / 100) AS bucket,
        ROW_NUMBER() OVER (PARTITION BY route_id, FLOOR(distance / 100) ORDER BY index) AS rn
    FROM point_data
)
SELECT
    route_id,
    index,
    latitude,
    longitude,
    elevation,
    distance
FROM bucketed
WHERE rn = 1
ORDER BY route_id, index