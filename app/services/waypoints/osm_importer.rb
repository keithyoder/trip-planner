# app/services/waypoints/osm_importer.rb
module Waypoints
  class OsmImporter
    def self.import(osm_poi_id, trip_id, sequence)
      new(osm_poi_id, trip_id, sequence).import
    end

    def initialize(osm_poi_id, trip_id, sequence)
      @osm_poi_id = osm_poi_id
      @trip_id    = trip_id
      @sequence   = sequence
    end

    def import
      osm_poi = OsmPoi.find_by(osm_id: @osm_poi_id)
      return unless osm_poi

      trip = Trip.find(@trip_id)
      seq  = resolve_sequence(trip)

      attrs = build_attributes(osm_poi, seq)
      Waypoint.create(attrs)
    rescue ActiveRecord::RecordNotUnique
      @sequence += 1
      retry
    end

    private

    def waypoint_type_and_delay(poi_type)
      case poi_type.to_sym
      when :fuel            then [:gas_station, 900]
      when :border_crossing then [:border_crossing, 1800]
      when :toll            then [:toll_booth,          0]
      when :ferry           then [:ferry_boarding,   1800]
      when :restaurant      then [:lunch,            3600]
      when :accommodation   then [:overnight,           0]
      when :tourism         then [:attraction, 1800]
      when :barrier         then [:attraction, 600]
      when :park            then [:attraction, 1800]
      when :laundry         then [:laundry, 900]
      when :place           then [:overnight,            0]
      else                       [:attraction,           0]
      end
    end

    def resolve_sequence(trip)
      taken = trip.waypoints
                  .where(sequence: @sequence..@sequence + 50)
                  .pluck(:sequence)
                  .to_set

      seq = (@sequence..@sequence + 50).find { |s| !taken.include?(s) } || @sequence + 51

      route = trip.routes
                  .joins(:waypoint_end)
                  .where('waypoints.sequence >= ?', seq)
                  .order('waypoints.sequence ASC')
                  .first

      seq -= 1 if route && seq == route.waypoint_end.sequence
      seq
    end

    def build_attributes(osm_poi, seq)
      waypoint_type, delay = waypoint_type_and_delay(osm_poi.poi_type)

      attrs = {
        trip_id: @trip_id,
        sequence: seq,
        waypoint_type: waypoint_type,
        delay: delay,
        name: osm_poi.name || osm_poi.metadata.dig('all_tags', 'note'),
        lonlat: osm_poi.lonlat,
        osm_poi_id: osm_poi.old_id
      }

      attrs[:toll] = osm_poi.toll_amount if osm_poi.toll_amount
      attrs
    end
  end
end
