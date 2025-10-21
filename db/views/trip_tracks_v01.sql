SELECT
    trip_id,
    ST_Union (geom::geometry)::geography AS geom,
    ST_Length (ST_Union (geom::geometry)::geography) AS distance
FROM
    routes
GROUP BY
    trip_id