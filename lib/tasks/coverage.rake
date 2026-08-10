# frozen_string_literal: true

namespace :coverage do
  desc 'Fetch Claro coverage for a trip track, clipped to a boundary, and print a summary. ' \
       'Usage: rake coverage:fetch[trip_id,layer,boundary_name]'
  task :fetch, %i[trip_id layer boundary_name] => :environment do |_t, args|
    trip_track = TripTrack.find(args[:trip_id])
    layer = args[:layer] || 'cobertura_externa_4G_UY'
    provider = 'claro'

    boundary = begin
      Boundary.find_unambiguous(args[:boundary_name])
    rescue ArgumentError => e
      puts e.message
      exit 1
    end

    puts "Fetching #{provider}/#{layer} coverage for trip #{trip_track.trip_id}" \
         "#{boundary ? " (clipped to #{boundary.name})" : ' (WARNING: full trip track, no boundary clip)'}..."

    fetcher = NetworkCoverage::ClaroFetcher.new(trip_track: trip_track, layer: layer, boundary: boundary)
    fetcher.call do |done, total, skipped|
      print "\r  #{done}/#{total} sample points (#{skipped} skipped, already covered)"
      $stdout.flush
    end
    puts

    summary = trip_track.coverage_summary(provider: provider, layer: layer, boundary: boundary)
    puts "Covered: #{(summary[:covered_distance_m] / 1000.0).round(1)} km"
    puts "Gap:     #{(summary[:gap_distance_m] / 1000.0).round(1)} km"
    puts "Percent covered: #{summary[:covered_pct]}%"
  end

  desc 'Fetch Claro Chile coverage for a trip track (via ArcGIS FeatureServer), clipped to a boundary. ' \
       'Usage: rake coverage:fetch_chile[trip_id,layer,boundary_name]'
  task :fetch_chile, %i[trip_id layer boundary_name] => :environment do |_t, args|
    trip_track = TripTrack.find(args[:trip_id])
    layer = args[:layer] || 'cobertura_movil_4G_CL'
    provider = 'claro'

    boundary = begin
      Boundary.find_unambiguous(args[:boundary_name])
    rescue ArgumentError => e
      puts e.message
      exit 1
    end

    puts "Fetching #{provider}/#{layer} coverage for trip #{trip_track.trip_id}" \
         "#{boundary ? " (clipped to #{boundary.name})" : ' (WARNING: full trip track, no boundary clip)'}..."

    fetcher = NetworkCoverage::ChileFetcher.new(trip_track: trip_track, layer: layer, boundary: boundary)
    fetcher.call do |done, total, skipped|
      print "\r  #{done}/#{total} sample points (#{skipped} skipped, already covered)"
      $stdout.flush
    end
    puts

    summary = trip_track.coverage_summary(provider: provider, layer: layer, boundary: boundary)
    puts "Covered: #{(summary[:covered_distance_m] / 1000.0).round(1)} km"
    puts "Gap:     #{(summary[:gap_distance_m] / 1000.0).round(1)} km"
    puts "Percent covered: #{summary[:covered_pct]}%"
  end

  desc 'Fetch Claro Brazil coverage for a trip track (via ArcGIS MapServer), clipped to a boundary. ' \
       'Usage: rake coverage:fetch_brazil[trip_id,layer,boundary_name]'
  task :fetch_brazil, %i[trip_id layer boundary_name] => :environment do |_t, args|
    trip_track = TripTrack.find(args[:trip_id])
    layer = args[:layer] || 'cobertura_movel_4G_BR'
    provider = 'claro'

    boundary = begin
      Boundary.find_unambiguous(args[:boundary_name])
    rescue ArgumentError => e
      puts e.message
      exit 1
    end

    puts "Fetching #{provider}/#{layer} coverage for trip #{trip_track.trip_id}" \
         "#{boundary ? " (clipped to #{boundary.name})" : ' (WARNING: full trip track, no boundary clip)'}..."

    fetcher = NetworkCoverage::BrazilFetcher.new(trip_track: trip_track, layer: layer, boundary: boundary)
    fetcher.call do |done, total, skipped|
      print "\r  #{done}/#{total} sample points (#{skipped} skipped, already covered)"
      $stdout.flush
    end
    puts

    summary = trip_track.coverage_summary(provider: provider, layer: layer, boundary: boundary)
    puts "Covered: #{(summary[:covered_distance_m] / 1000.0).round(1)} km"
    puts "Gap:     #{(summary[:gap_distance_m] / 1000.0).round(1)} km"
    puts "Percent covered: #{summary[:covered_pct]}%"
  end

  desc 'Fetch Claro Peru coverage for a trip track (district-driven static files). ' \
       'Usage: rake coverage:fetch_peru[trip_id,layer,boundary_name]'
  task :fetch_peru, %i[trip_id layer boundary_name] => :environment do |_t, args|
    trip_track = TripTrack.find(args[:trip_id])
    layer = args[:layer] || 'cobertura_movil_4G_adicional_PE'
    provider = 'claro'

    boundary = begin
      Boundary.find_unambiguous(args[:boundary_name])
    rescue ArgumentError => e
      puts e.message
      exit 1
    end

    if boundary.nil?
      puts 'coverage:fetch_peru requires a boundary_name (e.g. a department or province) — districts are looked up under it directly, no route-intersection check.'
      exit 1
    end

    puts "Fetching #{provider}/#{layer} coverage for trip #{trip_track.trip_id} (districts under #{boundary.name})..."

    fetcher = NetworkCoverage::PeruFetcher.new(trip_track: trip_track, layer: layer, boundary: boundary)
    tally = Hash.new(0)
    fetcher.call { |_done, _total, _name, status, _detail| tally[status] += 1 }
    puts "Done: #{tally.map { |k, v| "#{k}=#{v}" }.join(', ')}"

    summary = trip_track.coverage_summary(provider: provider, layer: layer, boundary: boundary)
    puts "Covered: #{(summary[:covered_distance_m] / 1000.0).round(1)} km"
    puts "Gap:     #{(summary[:gap_distance_m] / 1000.0).round(1)} km"
    puts "Percent covered: #{summary[:covered_pct]}%"
  end
  'Usage: rake coverage:export[trip_id,provider,layer,output_path]'
  task :export, %i[trip_id provider layer output_path] => :environment do |_t, args|
    scope = NetworkCoverage::Feature.all
    scope = scope.where(trip_id: args[:trip_id]) if args[:trip_id].present?
    scope = scope.where(provider: args[:provider]) if args[:provider].present?
    scope = scope.where(layer: args[:layer]) if args[:layer].present?

    output_path = args[:output_path].presence || 'coverage_features.geojson'

    rows = scope.connection.select_all(<<~SQL)
      SELECT id, trip_id, provider, layer, source_feature_id, fetched_at,
             ST_AsGeoJSON(geom) AS geom_json
      FROM (#{scope.to_sql}) AS filtered
    SQL

    features = rows.map do |row|
      {
        type: 'Feature',
        geometry: JSON.parse(row['geom_json']),
        properties: {
          id: row['id'],
          trip_id: row['trip_id'],
          provider: row['provider'],
          layer: row['layer'],
          source_feature_id: row['source_feature_id'],
          fetched_at: row['fetched_at']
        }
      }
    end

    File.write(output_path, { type: 'FeatureCollection', features: features }.to_json)
    puts "Exported #{features.size} features to #{output_path}"
  end

  desc 'Build a buffered-corridor coverage union and save it as a single GeoJSON Feature. ' \
       'Usage: rake coverage:export_union[trip_id,provider,layer,boundary_name,buffer_meters,output_path]'
  task :export_union, %i[trip_id provider layer boundary_name buffer_meters output_path] => :environment do |_t, args|
    trip_track = TripTrack.find(args[:trip_id])
    provider = args[:provider].presence || 'claro'
    layer = args[:layer]
    boundary = begin
      Boundary.find_unambiguous(args[:boundary_name])
    rescue ArgumentError => e
      puts e.message
      exit 1
    end
    buffer_meters = (args[:buffer_meters].presence || NetworkCoverage::Union::DEFAULT_BUFFER_METERS).to_i
    output_path = args[:output_path].presence || 'coverage_union.geojson'

    union = NetworkCoverage::Union.new(
      trip_track: trip_track,
      provider: provider,
      layer: layer,
      boundary: boundary,
      buffer_meters: buffer_meters
    )

    feature = union.to_geojson_feature

    if feature[:geometry].nil?
      puts 'No coverage found to union — check that the fetcher has run for this provider/layer/boundary.'
      exit 1
    end

    File.write(output_path, feature.to_json)
    puts "Wrote #{output_path} (#{feature[:properties][:feature_count]} source features, " \
         "#{buffer_meters}m corridor#{boundary ? ", clipped to #{boundary.name}" : ''})"
  end
end
