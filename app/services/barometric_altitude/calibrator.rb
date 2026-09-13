# frozen_string_literal: true

module BarometricAltitude
  # Converts BMP581 pressure readings into altitude using the standard
  # barometric formula, calibrated against a sea-level pressure (P0) that's
  # continuously re-derived from real driving data rather than the fixed
  # standard-atmosphere constant (1013.25 hPa) -- P0 genuinely drifts by
  # several hPa over the course of a day with real weather changes, and a
  # stale/wrong P0 shows up directly as an offset in every altitude reading
  # (e.g. an uncorrected day showed -30 to -42m below sea level for a
  # coastal city actually a few meters above it; a P0 that went 3+ hours
  # without recalibrating drifted ~7 hPa, ~55m of altitude error, before
  # the next real stop refreshed it).
  #
  # == Two calibration paths
  #
  # 1. STATIONARY (the primary, most trustworthy path): while parked,
  #    gps_speed stays below STATIONARY_SPEED_KMH, true altitude is
  #    constant by definition, and GPS altitude noise across many samples
  #    averages out cleanly. Confirmed empirically: stationary-window
  #    calibration measured stddev ~0.05-0.07 hPa, vs. ~1.5-1.75 hPa using
  #    all data (moving + stationary) over the same window -- a ~20-25x
  #    difference that held even after tightening the satellite-count
  #    filter, meaning the gap is the moving-altitude confound itself
  #    (true altitude changing sample to sample while driving, which no
  #    amount of averaging can distinguish from noise), not GPS signal
  #    quality.
  #
  # 2. MOVING FALLBACK (last resort only): if no stationary window has
  #    occurred in over MOVING_CALIBRATION_MAX_AGE, P0 is instead derived
  #    from the last MOVING_CALIBRATION_SAMPLE_COUNT rows of real
  #    telemetry (regardless of speed), on the reasoning that "somewhat
  #    noisier than ideal" beats "confidently wrong by hours of drift" once
  #    staleness has grown large enough. This is NOT a peer to stationary
  #    calibration -- it inherits all of stationary calibration's
  #    weaknesses (GPS altitude noise, and worse, real terrain elevation
  #    change corrupting the average) with none of its noise-cancellation
  #    guarantee. It is deliberately gated to fire only when P0 is already
  #    stale, and throttled (MOVING_CALIBRATION_RETRY_INTERVAL) so a long
  #    stale stretch doesn't requery the DB on every single reading.
  #    Verified against a real stretch of driving where P0 was known-good
  #    (confirmed via an independent stationary calibration immediately
  #    before and after): a naive moving-window average over that same
  #    stretch converged within a few hundredths of a hPa of the known
  #    value when the window didn't happen to include unusual terrain --
  #    but was measurably off when it did. This fallback accepts that
  #    imprecision as the cost of not running on a multi-hour-stale P0.
  #
  # == Buffer lifecycle
  #
  # The stationary buffer clears after each successful recalibration
  # rather than growing indefinitely while parked -- without that, a long
  # stop kept recalibrating on every single new sample once the threshold
  # was first crossed (30, 31, 32... continuing for as long as the car
  # stayed still), with the buffer's ever-growing history slowly dragging
  # the running average toward whatever the newest few readings happened
  # to be (observed in production as altitude drifting ~2m over a minute
  # while genuinely parked). Clearing after each calibration makes each
  # one a fresh, independent estimate from its own bounded batch of
  # samples instead of one perpetually-recomputed average.
  #
  # == Persistence
  #
  # State (the in-progress stationary buffer, current best P0, and when it
  # was last set) is kept in Rails.cache (Redis in production), so it
  # survives TelemetrySyncService restarts. The buffer's own 1-hour expiry
  # is a safety net against ever mixing samples from two unrelated stops
  # separated by an oddly long, sparse gap into one nonsensical average --
  # NOT a mechanism that fires during an ordinary short errand while the
  # Pi is powered off, since the car not moving during that gap means
  # every sample before and after it still legitimately represents the
  # same true altitude either way.
  #
  # == Late-arriving data
  #
  # This class only ever sees data that TelemetrySyncService chooses to
  # pass it -- it has no way to know if a reading was delayed in transit.
  # Confirmed in production: a RabbitMQ redelivery caused a handful of
  # readings to be processed ~6.5 hours after their real timestamp,
  # landing after P0 had already moved on. Any altitude computed from
  # those readings at write-time was silently wrong -- correct for
  # whenever it was actually processed, not for the historical moment it
  # claimed to represent. TelemetrySyncService is responsible for not
  # calling Calibrator.altitude_for at all when a message's processing
  # delay exceeds a threshold (see MAX_PROCESSING_DELAY there) -- this
  # class has no visibility into that and can't defend against it itself.
  class Calibrator
    STATIONARY_SPEED_KMH = 2
    MIN_STATIONARY_SECONDS = 60
    MIN_SAMPLES = 30
    MAX_BUFFER_SAMPLES = 120 # ~8 min at a 4s cadence -- bounds how far a long stop can grow the buffer
    MIN_SATELLITES = 5
    DEFAULT_P0 = 1013.25
    BUFFER_TTL = 1.hour

    MOVING_CALIBRATION_MAX_AGE = 1.hour
    MOVING_CALIBRATION_SAMPLE_COUNT = 150
    MOVING_CALIBRATION_MIN_VALID_SAMPLES = 100
    MOVING_CALIBRATION_RETRY_INTERVAL = 5.minutes

    P0_CACHE_KEY = 'barometric_altitude/current_p0'
    CALIBRATED_AT_CACHE_KEY = 'barometric_altitude/calibrated_at'
    BUFFER_CACHE_KEY = 'barometric_altitude/stationary_buffer'
    MOVING_ATTEMPT_CACHE_KEY = 'barometric_altitude/last_moving_attempt'

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

      # @return [Time, nil] when current_p0 was last set, or nil if never
      def calibrated_at
        Rails.cache.read(CALIBRATED_AT_CACHE_KEY)
      end

      # @param as_of [Time] typically the timestamp of the reading being
      #   processed, not Time.current -- so staleness is judged relative
      #   to the data's own timeline, not wall-clock time (important if
      #   ever processing delayed/backfilled data).
      # @return [Boolean] true if no calibration has ever happened, or the
      #   last one is older than MOVING_CALIBRATION_MAX_AGE
      def stale?(as_of)
        age = calibrated_at ? as_of - calibrated_at : Float::INFINITY
        age > MOVING_CALIBRATION_MAX_AGE
      end

      # Call once per incoming TelemetryLog, after it's saved. Tracks a
      # rolling "currently stationary" buffer; any real movement clears
      # it immediately (a partial stationary window mixed with driving
      # would reintroduce the moving-altitude confound). Once the buffer
      # has enough samples over enough time, recalibrates P0 from it and
      # starts a fresh buffer for the next batch.
      #
      # While moving, if P0 has gone stale (see stale?), attempts the
      # moving-fallback calibration instead -- see class docs for why
      # this is a last resort, not a routine path.
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
          maybe_calibrate_while_moving(timestamp) if stale?(timestamp)
        end
      end

      private

      def accumulate(pressure, gps_altitude, timestamp)
        buffer = Rails.cache.read(BUFFER_CACHE_KEY) || []
        buffer << { pressure: pressure, altitude: gps_altitude, timestamp: timestamp }
        buffer = buffer.last(MAX_BUFFER_SAMPLES)

        if ready_to_calibrate?(buffer)
          recalibrate(buffer, timestamp)
          Rails.cache.delete(BUFFER_CACHE_KEY)
        else
          Rails.cache.write(BUFFER_CACHE_KEY, buffer, expires_in: BUFFER_TTL)
        end
      end

      def ready_to_calibrate?(buffer)
        buffer.length >= MIN_SAMPLES &&
          (buffer.last[:timestamp] - buffer.first[:timestamp]) >= MIN_STATIONARY_SECONDS
      end

      def recalibrate(buffer, as_of)
        fixed_altitude = buffer.sum { |r| r[:altitude] } / buffer.length.to_f
        implied_p0s = buffer.map { |r| r[:pressure] / (1 - fixed_altitude / 44_330.0)**(1 / 0.1903) }
        mean = implied_p0s.sum / implied_p0s.length

        store_p0(mean, as_of)
        Rails.logger.info "[BarometricAltitude] Recalibrated P0=#{mean.round(2)} hPa (stationary) " \
                           "from #{buffer.length} samples (altitude=#{fixed_altitude.round(1)}m)"
      end

      # Fallback for long stretches with no qualifying stop. Uses the
      # MOVING_CALIBRATION_SAMPLE_COUNT most recent qualifying telemetry
      # rows at or before `as_of` -- queried from the DB by timestamp, not
      # taken from in-process state, so a late-arriving/backfilled reading
      # can't corrupt this the way it corrupted write-time
      # barometric_altitude before TelemetrySyncService's own guard was
      # added. Throttled via MOVING_ATTEMPT_CACHE_KEY so a long stale
      # stretch doesn't run this query on every single incoming reading.
      #
      # @param as_of [Time]
      def maybe_calibrate_while_moving(as_of)
        last_attempt = Rails.cache.read(MOVING_ATTEMPT_CACHE_KEY)
        return if last_attempt && (as_of - last_attempt) < MOVING_CALIBRATION_RETRY_INTERVAL

        Rails.cache.write(MOVING_ATTEMPT_CACHE_KEY, as_of, expires_in: MOVING_CALIBRATION_RETRY_INTERVAL)

        rows = TelemetryLog
               .where('timestamp <= ?', as_of)
               .where.not("data->>'bmp581_pressure' IS NULL")
               .where.not("data->>'gps_altitude' IS NULL")
               .where("COALESCE((data->>'gps_satellites')::int, 0) >= ?", MIN_SATELLITES)
               .order(timestamp: :desc)
               .limit(MOVING_CALIBRATION_SAMPLE_COUNT)
               .pluck(Arel.sql("(data->>'bmp581_pressure')::float"), Arel.sql("(data->>'gps_altitude')::float"))

        return if rows.length < MOVING_CALIBRATION_MIN_VALID_SAMPLES

        implied_p0s = rows.map { |p, alt| p / (1 - alt / 44_330.0)**(1 / 0.1903) }
        mean = implied_p0s.sum / implied_p0s.length

        store_p0(mean, as_of)
        Rails.logger.info "[BarometricAltitude] Recalibrated P0=#{mean.round(2)} hPa (moving fallback, " \
                           "was stale) from #{rows.length} recent samples"
      rescue StandardError => e
        Rails.logger.warn("[BarometricAltitude] Moving calibration failed: #{e.message}")
      end

      def store_p0(value, as_of)
        Rails.cache.write(P0_CACHE_KEY, value)
        Rails.cache.write(CALIBRATED_AT_CACHE_KEY, as_of)
      end
    end
  end
end
