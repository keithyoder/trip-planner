class EnvironmentLogAggregator
  BUCKET_SECONDS = 60
  MIN_SATELLITES = 4

  # LTR390 default gain (3) / resolution (20-bit) / WFAC=1. Confirm this
  # matches the Pi's actual sensor init settings -- if the driver ever
  # changes gain/resolution, this constant needs to change with it.
  UV_SENSITIVITY = 1400

  LOCATION_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326, has_z_coordinate: true)

  def self.aggregate_bucket(bucket_start)
    bucket_end = bucket_start + BUCKET_SECONDS
    midpoint = bucket_start + (BUCKET_SECONDS / 2)

    logs = TelemetryLog.where(timestamp: bucket_start...bucket_end).select { |l| reliable_fix?(l) }
    return if logs.empty?

    temperature = median(logs.filter_map { |l| l.data['shtc3_temperature'] })
    humidity    = median(logs.filter_map { |l| l.data['shtc3_humidity'] })
    pressure    = median(logs.filter_map { |l| l.data['bmp581_pressure'] })
    uv_index    = median(logs.filter_map { |l| uv_index_from_counts(l.data['ltr390_uv_index']) })

    return if [temperature, humidity, pressure, uv_index].all?(&:nil?)

    midpoint_log = logs.min_by { |l| (l.timestamp - midpoint).abs }
    location = build_location(midpoint_log)
    timezone = Boundary.timezone_at(midpoint_log.data['gps_longitude'].to_f, midpoint_log.data['gps_latitude'].to_f)

    EnvironmentLog.upsert(
      {
        bucket_start: bucket_start,
        bucket_end: bucket_end,
        sample_count: logs.count,
        location: location,
        timezone: timezone,
        trip_id: Trip.current&.id,
        temperature: temperature,
        humidity: humidity,
        pressure: pressure,
        uv_index: uv_index,
        created_at: Time.current,
        updated_at: Time.current
      },
      unique_by: :bucket_start
    )
  end

  def self.reliable_fix?(log)
    (log.data['gps_satellites'] || 0) >= MIN_SATELLITES
  end

  def self.uv_index_from_counts(raw_count)
    return nil if raw_count.nil?

    (raw_count / UV_SENSITIVITY).round(2)
  end

  def self.build_location(log)
    lon = log.data['gps_longitude'].to_f
    lat = log.data['gps_latitude'].to_f
    elevation = log.data['gps_altitude']&.to_f || 0

    LOCATION_FACTORY.point(lon, lat, elevation)
  end

  def self.median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.size / 2

    sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round(2)
  end
end
