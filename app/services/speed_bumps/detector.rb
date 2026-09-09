module SpeedBumps
  class Detector
    DEFAULT_FROM_KMH = 40
    DEFAULT_TO_KMH = 20
    DEFAULT_MAX_SECONDS = 15
    DEFAULT_RECOVERY_KMH = 30
    DEFAULT_RECOVERY_SECONDS = 30
    DEFAULT_MIN_BOTTOM_KMH = 3
    MERGE_WINDOW_SECONDS = 30

    def initialize(from_kmh: DEFAULT_FROM_KMH, to_kmh: DEFAULT_TO_KMH, max_seconds: DEFAULT_MAX_SECONDS,
                   recovery_kmh: DEFAULT_RECOVERY_KMH, recovery_seconds: DEFAULT_RECOVERY_SECONDS,
                   min_bottom_kmh: DEFAULT_MIN_BOTTOM_KMH)
      @from_kmh = from_kmh
      @to_kmh = to_kmh
      @max_seconds = max_seconds
      @recovery_kmh = recovery_kmh
      @recovery_seconds = recovery_seconds
      @min_bottom_kmh = min_bottom_kmh
    end

    def detect(start_time, end_time)
      rows = TelemetryLog.between(start_time, end_time)
                         .where.not("data->>'gps_speed' IS NULL")
                         .where("COALESCE((data->>'gps_satellites')::int, 0) > 0")
                         .order(:timestamp)
                         .pluck(:timestamp, Arel.sql("(data->>'gps_speed')::float * 3.6"),
                                Arel.sql("(data->>'gps_latitude')::float"), Arel.sql("(data->>'gps_longitude')::float"))

      events = []
      rows.each_with_index do |(t, speed, lat, lon), i|
        next if speed > to_kmh || speed < min_bottom_kmh

        j = i - 1
        while j >= 0 && (t - rows[j][0]) <= max_seconds
          prev_t, prev_speed, = rows[j]
          if prev_speed >= from_kmh && recovers?(rows, i, t)
            events << { from_time: prev_t, to_time: t, from_speed: prev_speed.round(1),
                        to_speed: speed.round(1), duration: (t - prev_t).round(1), lat: lat, lon: lon }
            break
          end
          j -= 1
        end
      end

      events.chunk_while { |a, b| b[:from_time] - a[:to_time] < MERGE_WINDOW_SECONDS }.map(&:first)
    end

    private

    attr_reader :from_kmh, :to_kmh, :max_seconds, :recovery_kmh, :recovery_seconds, :min_bottom_kmh

    def recovers?(rows, dip_index, dip_time)
      k = dip_index + 1
      while k < rows.size && (rows[k][0] - dip_time) <= recovery_seconds
        return true if rows[k][1] >= recovery_kmh

        k += 1
      end
      false
    end
  end
end
