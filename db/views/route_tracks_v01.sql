SELECT
    ST_Union (geom::geometry)::geography AS track,
    ST_Length (ST_Union (geom::geometry)::geography) AS distance
FROM
    routes
