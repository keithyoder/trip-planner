# frozen_string_literal: true

require 'test_helper'

module Trips
  class GpxExporterTest < ActiveSupport::TestCase
    include LandingTripHelpers

    # Eleven points a minute apart that go out and back along a V (the peak is point 5),
    # so every point except the three corners lies exactly on a straight stretch.
    COORDS = (0..10).map do |i|
      [-46.6 + (0.002 * [i, 10 - i].min), -23.0 - (0.01 * i), 100 + i, i * 60]
    end

    setup do
      Trip.destroy_all
      @trip = Trip.create!(name: 'GPX trip', start_on: Date.new(2027, 1, 30))
      add_route(@trip, from_seq: 100, to_seq: 200, lat_from: -23.0, lat_to: -23.1)
      @route = @trip.routes.first
      points = COORDS.map { |lon, lat, ele, m| "#{lon} #{lat} #{ele} #{m}" }.join(', ')
      Route.where(id: @route.id).update_all(
        "geom = ST_GeogFromText('SRID=4326;LINESTRING ZM(#{points})'), start_time = '8 hours'"
      )
    end

    def export(**options)
      Nokogiri::XML(GpxExporter.new(@trip, **options).to_gpx).remove_namespaces!
    end

    def track_times(doc)
      doc.xpath('//trkpt').map { |pt| [pt['lat'].to_f, Time.iso8601(pt.at('time').text)] }
    end

    test 'writes one track per day with every point, elevation and a time' do
      doc = export

      assert_equal 1, doc.xpath('//trk').size
      assert_equal 11, doc.xpath('//trkpt').size
      assert_equal %w[100.0 105.0 110.0], doc.xpath('//trkpt/ele').to_a.values_at(0, 5, 10).map(&:text)
      assert_match(/\A2027-01-30 – /, doc.at('//trk/name').text)
    end

    test 'times are the day start plus each point\'s own offset' do
      times = track_times(export).map(&:last)

      assert_equal (0..10).map { |i| times.first + (i * 60) }, times
      assert_equal [8, 0], [times.first.hour, times.first.min] # start_time of 8 hours, fallback zone has no offset
    end

    test 'simplifying drops points on a straight stretch and keeps the corners' do
      doc = export(tolerance_m: 25)

      assert_equal([-23.0, -23.05, -23.1], doc.xpath('//trkpt').map { |pt| pt['lat'].to_f })
    end

    test 'a point that survives keeps the time it had in the full export' do
      full = track_times(export).to_h
      simplified = track_times(export(tolerance_m: 25))

      assert_equal 3, simplified.size
      simplified.each { |lat, time| assert_equal full[lat], time }
    end

    test 'a tolerance wider than the detour straightens the whole line, but never loses the ends' do
      lats = export(tolerance_m: 5_000).xpath('//trkpt').map { |pt| pt['lat'].to_f }

      assert_equal [-23.0, -23.1], lats
    end

    test 'a stop is never thinned away, and still gets its hold point' do
      Waypoint.where(trip: @trip, sequence: 100).update_all(delay: 600)
      Route.where(id: @route.id).update_all(segments: [{ 'steps' => [{ 'way_points' => [2, 10] }] }])
      doc = export(tolerance_m: 25)
      stop = doc.xpath('//trkpt').select { |pt| (pt['lat'].to_f + 23.02).abs < 1e-9 }

      assert_equal 2, stop.size # arrival and, ten minutes later, departure
      assert_equal 600, (Time.iso8601(stop[1].at('time').text) - Time.iso8601(stop[0].at('time').text))
    end

    test 'the arrival waypoint is a wpt marker at its own point' do
      Route.where(id: @route.id).update_all(segments: [{ 'steps' => [{ 'way_points' => [0, 10] }] }])
      doc = export(tolerance_m: 25)

      assert_equal %w[wp100 wp200], doc.xpath('//wpt/name').map(&:text).sort
    end

    test 'a small trip is one file, and the daily export hands back each day\'s route sequence' do
      exporter = GpxExporter.new(@trip)
      daily = exporter.to_daily_gpx_files

      assert_equal 1, exporter.to_gpx_files.size
      assert_equal([@route.id], daily.map { |d| d[:route_sequence].route_id })
      assert_equal 11, Nokogiri::XML(daily.first[:gpx]).remove_namespaces!.xpath('//trkpt').size
    end

    test 'a route with invalid geometry is skipped rather than exported empty' do
      Route.where(id: @route.id).update_all(geom: nil)

      assert_empty GpxExporter.new(@trip).to_gpx_files
    end
  end
end
