# frozen_string_literal: true

class OverpassController < ApplicationController
  before_action :set_trip_and_route, only: %i[index create import_waypoint]

  def index
    @categories = Overpass::CATEGORIES.keys
  end

  def create
    @node_type = params[:type].to_sym

    redirect_to trip_route_overpass_path(@trip, @route, @node_type)
  end

  def show
    @trip = Trip.find(params[:trip_id])
    @route = @trip.routes.with_bbox.find(params[:route_id])
    @node_type = params[:type].to_sym

    unless Overpass::CATEGORIES.key?(@node_type)
      redirect_to trip_route_overpass_path(@trip, @route), alert: 'Invalid POI type'
      return
    end

    Rails.logger.debug "BBOX: s=#{@route.bbox_s} n=#{@route.bbox_n} w=#{@route.bbox_w} e=#{@route.bbox_e}"
    @overpass = Overpass.new(@route.id, @node_type)
    @pois = @overpass.close_to_route

    cache_key = "overpass_#{@route.id}_#{@node_type}"
    Rails.cache.write(cache_key, @pois, expires_in: 1.hour)
    session[:overpass_cache_key] = cache_key
  rescue JSON::ParserError
    Rails.logger.error "Overpass XML response: #{@response.inspect}"
    raise
  end

  def import_waypoint
    osm_id = params[:osm_id]
    cache_key = session[:overpass_cache_key]
    pois = Rails.cache.read(cache_key)
    puts pois
    unless pois
      render json: {
        success: false,
        message: 'Session expired. Please search again.'
      }, status: :unprocessable_entity
      return
    end

    # Find the POI in the cached data
    poi = pois.find do |p|
      "#{p[:type]}_#{p[:id]}" == osm_id
    end

    unless poi
      render json: {
        success: false,
        message: 'POI not found in session'
      }, status: :not_found
      return
    end

    # Import the POI
    begin
      # Use the service object
      osm_poi = OsmPoiImporter.import_from_overpass(poi, params['type'].to_sym)

      # Calculate the appropriate sequence based on route position
      sequence = Waypoint.calculate_sequence_for_position(@trip, @route, osm_poi.geom.lat, osm_poi.geom.lon)

      # Create waypoint from osm_poi
      waypoint = Waypoints::OsmImporter.import(osm_poi.osm_id, @trip.id, sequence)

      if waypoint
        render json: {
          success: true,
          message: "Waypoint imported at sequence #{sequence}",
          waypoint_id: waypoint.id,
          sequence: sequence
        }
      else
        render json: {
          success: false,
          message: 'Failed to create waypoint'
        }, status: :unprocessable_entity
      end
    rescue StandardError => e
      Rails.logger.error "Import error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: {
        success: false,
        message: "Error importing waypoint: #{e.message}"
      }, status: :unprocessable_entity
    end
  end

  private

  def set_trip_and_route
    @trip = Trip.find(params[:trip_id])
    route_columns = Route.column_names.reject { |col| %w[geom segments].any? col }

    @route = @trip.routes
                  .select(route_columns)
                  .find(params[:route_id])
  end

  def import_osm_poi(poi)
    node_type = session[:overpass_data]['node_type'].to_sym

    osm_poi = OsmPoi.find_or_initialize_by(osm_id: "#{poi['type']}_#{poi['id']}")

    # metadata = osm_poi.extract_metadata(poi['tags'], node_type)

    osm_poi.update!(
      osm_type: poi['type'],
      name: poi.dig('tags', 'name'),
      poi_type: node_type,
      city: poi.dig('tags', 'addr:city'),
      street: poi.dig('tags', 'addr:street'),
      district: poi.dig('tags', 'addr:suburb'),
      geom: create_geometry(poi)
      # metadata: metadata
    )

    osm_poi
  end
end
