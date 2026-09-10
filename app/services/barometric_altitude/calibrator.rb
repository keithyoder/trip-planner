# frozen_string_literal: true

module BarometricAltitude
  # Converts BMP581 pressure readings into altitude using the standard
  # barometric formula, calibrated against a sea-level pressure (P0) that's
  # continuously re-derived from real driving data rather than the fixed
  # standard-atmosphere constant (1013.25 hPa) -- P0 genuinely drifts by
  # roughly 0.1-1 hPa over the course of a day with real weather changes,
  # and a stale/wrong P0 shows up directly as an offset in every altitude
  # reading (e.g. an uncorrected day showed -30m below sea level for a
  # coastal city actually a few meters above it).
  #
  # Calibration only ever happens from STATIONARY windows (gps_speed
  # consistently below STATIONARY_SPEED_KMH), never while driving. While
  # parked, true altitude is constant by definition, so GPS altitude noise
  # across many samples averages out cleanly. While driving, true altitude
  # is genuinely changing sample to sample, so there's no valid way to
  # average away GPS noise without also blurring real signal -- confirmed
  # empirically: stationary-window calibration measured stddev ~0.05-0.07
  # hPa, vs. ~1.5-1.75 hPa using all data (moving + stationary) over the
  # same window, a ~20-25x difference that held even after tightening the
  # satellite-count filter, meaning the gap is the moving-altitude
  # confound itself, not GPS signal quality.
  #
  # State (the in-progress stationary buffer, and the current best P0) is
  # kept in Rails.cache (Redis in production), so it survives
  # TelemetrySyncService restarts. The buffer's own 1-hour expiry is
  # deliberate: it's a safety net against ever mixing samples from two
  # unrelated stops separated by an oddly long, sparse gap into one
  # nonsensical average -- NOT a mechanism that fires during an ordinary
  # short errand while the Pi is powered off, since the car not moving
  # during that gap means every sample before and after it still
  # legitimately represents the same true altitude either way.
  class Calibrator
    STATIONARY_SPEED_KMH = 2
    MIN_STATIONARY_SECONDS = 60
    MIN_SAMPLES = 30
    MIN_SATELLITES = 5
    DEFAULT_P0 = 1013.25
    BUFFER_TTL = 1.hour

    P0_CACHE_KEY = 'barometric_altitude/current_p0'
    BUFFER_CACHE_KEY = 'barometric_altitude/stationary_buffer'

    class << self
      # @param pressure [Float] hPa
      # @return [Float] altitude in meters, using the current best-known P0
      def altitude_for(pressure)
        44_330.0 * (1 - (pressure / current_p0)**0.1903)
      end

      # @return [Float] current calibrated sea-level pressure, or the
      #   standard-atmosphere default if no calibration has happened yet
      #   (e.g. right after a fresh deploy/restart before any qualifying
      #   stationary window has occurred)
      def current_p0
        Rails.cache.read(P0_CACHE_KEY) || DEFAULT_P0
      end

      # Call once per incoming TelemetryLog, after it's saved. Tracks a
      # rolling "currently stationary" buffer; any real movement clears
      # it immediately (a partial stationary window mixed with driving
      # would reintroduce the moving-altitude confound), and once the
      # buffer has enough samples over enough time, recalibrates P0 from
      # it.
      #
      # @param pressure [Float, nil]
      # @param gps_altitude [Float, nil]
      # @param gps_speed_kmh [Float]
      # @param satellites [Integer, nil]
      # @param timestamp [Time]
      def observe(pressure:, gps_altitude:, gps_speed_kmh:, satellites:, timestamp:)
        return if pressure.nil? || gps_altitude.nil?
        return if satellites.to_i < MIN_SATELLITES

        if gps_speed_kmh < STATIONARY_SPEED_KMH
          accumulate(pressure, gps_altitude, timestamp)
        else
          Rails.cache.delete(BUFFER_CACHE_KEY)
        end
      end

      private

      def accumulate(pressure, gps_altitude, timestamp)
        buffer = Rails.cache.read(BUFFER_CACHE_KEY) || []
        buffer << { pressure: pressure, altitude: gps_altitude, timestamp: timestamp }
        Rails.cache.write(BUFFER_CACHE_KEY, buffer, expires_in: BUFFER_TTL)

        return unless ready_to_calibrate?(buffer)

        recalibrate(buffer)
      end

      def ready_to_calibrate?(buffer)
        buffer.length >= MIN_SAMPLES &&
          (buffer.last[:timestamp] - buffer.first[:timestamp]) >= MIN_STATIONARY_SECONDS
      end

      def recalibrate(buffer)
        fixed_altitude = buffer.sum { |r| r[:altitude] } / buffer.length.to_f
        implied_p0s = buffer.map { |r| r[:pressure] / (1 - fixed_altitude / 44_330.0)**(1 / 0.1903) }
        mean = implied_p0s.sum / implied_p0s.length

        Rails.cache.write(P0_CACHE_KEY, mean)
        Rails.logger.info "[BarometricAltitude] Recalibrated P0=#{mean.round(2)} hPa " \
                           "from #{buffer.length} stationary samples (altitude=#{fixed_altitude.round(1)}m)"
      end
    end
  end
end
