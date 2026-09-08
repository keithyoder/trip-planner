# frozen_string_literal: true

module TripLogs
  class DaySummaryPresenter
    include LocalizedUnits

    def initialize(summary, fuel_used, locale: I18n.locale)
      @summary = summary
      @fuel_used = fuel_used
      @locale = locale
    end

    def distance
      localized(summary[:total_distance], 2).to_s(units: true)
    end

    def duration
      seconds = summary[:total_duration_seconds].to_i
      "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
    end

    def max_speed
      localized(Units::Speed.new(summary[:max_speed_mps]), 1).to_s(units: true)
    end

    def segments
      summary[:total_trips]
    end

    def fuel_used
      localized(fuel_used_value, 2).to_s(units: true)
    end

    def fuel_efficiency
      return '—' unless summary[:total_distance].positive?

      localized(fuel_used_value / summary[:total_distance], 1).to_s(units: true)
    end

    private

    attr_reader :summary, :locale

    def fuel_used_value
      @fuel_used
    end
  end
end
