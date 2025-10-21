SELECT
    routes.id AS route_id,
    (dp).path[1] AS index,
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
        routes) AS route_points,
    routes
WHERE
    route_points.id = routes.id