class OsmPoi < ApplicationRecord
  has_one :waypont
  enum poi_type: {
    fuel: 1,
    camping: 2,
    ferry: 3,
    border_crossing: 4,
    toll: 5
  }

  def self.import
    ActiveRecord::Base.connection.execute(
        <<~SQL
            insert into osm_pois
            select
                replace(replace(id, 'node/', ''), 'way/', '')::bigint,
                osm_poi_import.name,
                5,
                "addr:city",
                "addr:country",
                "addr:district",
                "addr:housenumber",
                "addr:milestone",
                "addr:postcode",
                "addr:province",
                "addr:state",
                "addr:street",
                ST_Centroid(wkb_geometry),
                current_timestamp,current_timestamp 
            from
                osm_poi_import,
                route_tracks
            where
                ST_DWithin(route_tracks.track, osm_poi_import.wkb_geometry::geography, 5)
            ON CONFLICT (id) DO UPDATE
              SET name = EXCLUDED.name,
                city = EXCLUDED.city,
                country = EXCLUDED.country,
                district = EXCLUDED.district,
                housenumber = EXCLUDED.housenumber,
                milestone = EXCLUDED.milestone,
                postcode = EXCLUDED.postcode,
                province = EXCLUDED.province,
                state = EXCLUDED.state,
                street = EXCLUDED.street,
                geom = EXCLUDED.geom
        SQL
    )
  end
end
