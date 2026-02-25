# frozen_string_literal: true

module Routes
  module ElevationAnalysis
    extend ActiveSupport::Concern

    included do
      # Returns a memoized analyzer for this route's elevation profile.
      #
      # @return [Routes::ElevationAnalyzer]
      def elevation_analysis(bucket_size: DEFAULT_BUCKET_SIZE_METERS)
        @elevation_analysis_cache ||= {}
        @elevation_analysis_cache[bucket_size] ||= Routing::ElevationAnalyzer.new(elevations(bucket_size: bucket_size))
      end
    end
  end
end
