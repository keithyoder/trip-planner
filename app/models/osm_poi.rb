# frozen_string_literal: true

# == Schema Information
#
# Table name: osm_pois
#
#  id          :bigint           not null, primary key
#  name        :string
#  poi_type    :integer
#  city        :string
#  country     :string
#  district    :string
#  housenumber :string
#  milestone   :string
#  postcode    :string
#  province    :string
#  state       :string
#  street      :string
#  geom        :geography        point, 4326
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class OsmPoi < ApplicationRecord
  has_one :waypont
  enum :poi_type, {
    fuel: 1,
    accommodation: 2,
    ferry: 3,
    border_crossing: 4,
    toll: 5,
    restaurant: 6,
    tourism: 7,
    barrier: 8,
    parking: 9,
    bank: 10,
    park: 11
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
            current_timestamp,current_timestamp#{' '}
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

  def toll_amount
    return nil unless metadata.present? && poi_type == 'toll'

    toll_value = metadata['toll_motorcar'] ||
                 metadata['toll'] ||
                 metadata['charge']

    parse_toll_amount(toll_value) if toll_value
  end

  def lonlat
    return geom if geom.geometry_type == RGeo::Feature::Point

    geom.centroid
  end

  private

  def parse_toll_amount(toll_string)
    match = toll_string.to_s.match(/[\d,.]+/)
    return nil unless match

    match[0].gsub(',', '.').to_d
  rescue StandardError
    nil
  end
end
