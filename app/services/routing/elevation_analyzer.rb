# frozen_string_literal: true

module Routing
  # Analyzes an elevation profile produced by Routes::ElevationProfile#elevations.
  # Accepts an array of ElevationPoint value objects and provides statistics,
  # terrain classification, cumulative gain/loss, and peak/valley detection.
  #
  # @example
  #   route.elevation_analysis.statistics
  #   route.elevation_analysis.peaks_and_valleys
  #   route.elevation_analysis.highest_point
  #
  class ElevationAnalyzer
    # Minimum elevation change between consecutive points to count as
    # real climbing/descending rather than sensor/DEM noise.
    NOISE_THRESHOLD_METERS = 5.0

    # @param points [Array<Routes::ElevationProfile::ElevationPoint>]
    def initialize(points)
      @points = points
    end

    # ------------------------------------------------------------------ #
    # Extremes
    # ------------------------------------------------------------------ #

    # @return [ElevationPoint, nil]
    def highest_point
      @highest_point ||= @points.max_by(&:elevation)
    end

    # @return [ElevationPoint, nil]
    def lowest_point
      @lowest_point ||= @points.min_by(&:elevation)
    end

    # @return [Float] difference in elevation units between highest and lowest
    def elevation_range
      return 0.0 if @points.empty?

      highest_point.elevation - lowest_point.elevation
    end

    # ------------------------------------------------------------------ #
    # Statistics
    # ------------------------------------------------------------------ #

    # Returns a hash of descriptive statistics and a terrain classification.
    #
    # Keys:
    #   :count, :min, :max, :mean, :stddev,
    #   :q1, :median, :q3, :iqr,
    #   :cv_pct       — stddev / mean * 100; normalises spread by average altitude
    #   :terrain_class — :flat | :rolling | :hilly | :mountainous
    #
    # @return [Hash, nil] nil when there are no elevation points
    def statistics
      @statistics ||= compute_statistics
    end

    # ------------------------------------------------------------------ #
    # Terrain classification
    # ------------------------------------------------------------------ #

    # Classifies terrain from stddev and IQR (both in the profile's elevation unit).
    # stddev captures overall spread including outlier peaks.
    # IQR    captures the typical middle-50% spread, resistant to outliers.
    # Thresholds assume meters; they will be less meaningful for feet profiles.
    #
    # @param stddev [Float]
    # @param iqr    [Float]
    # @return [Symbol] :flat | :rolling | :hilly | :mountainous
    def classify_terrain(stddev, iqr)
      if    stddev < 50  && iqr < 40  then :flat
      elsif stddev < 150 && iqr < 120 then :rolling
      elsif stddev < 300 && iqr < 250 then :hilly
      else :mountainous
      end
    end

    # ------------------------------------------------------------------ #
    # Cumulative gain / loss
    # ------------------------------------------------------------------ #

    # Sums uphill and downhill elevation changes, ignoring steps smaller
    # than NOISE_THRESHOLD_METERS to avoid inflating totals with DEM jitter.
    #
    # @param noise_threshold [Float] minimum delta to count (elevation units)
    # @return [Hash] { gain: Float, loss: Float }
    def elevation_gain_loss(noise_threshold: NOISE_THRESHOLD_METERS)
      gain = 0.0
      loss = 0.0

      @points.each_cons(2) do |a, b|
        diff = b.elevation - a.elevation
        next if diff.abs < noise_threshold

        diff > 0 ? gain += diff : loss += diff.abs
      end

      { gain: gain.round(1), loss: loss.round(1) }
    end

    # ------------------------------------------------------------------ #
    # Peak / valley detection
    # ------------------------------------------------------------------ #

    # Detects significant peaks and valleys in the elevation profile.
    #
    # Algorithm:
    #   1. Smooth the raw elevation values with a centred moving average to
    #      suppress noise without losing major terrain features.
    #   2. Find sign changes in the first derivative (slope reversals).
    #   3. Filter candidates by prominence — each must be at least
    #      `prominence` units above/below its flanking opposite features.
    #
    # @param smooth_window [Integer] number of points in the moving average window
    # @param prominence    [Float]   minimum height delta vs. flanking features
    # @return [Array<Hash>] each entry:
    #   {
    #     type:      :peak | :valley,
    #     index:     Integer,          # position in the original points array
    #     latitude:  Float,
    #     longitude: Float,
    #     elevation: Float,            # in the profile's elevation unit
    #     distance:  Units::Distance   # from route start, already unit-converted
    #   }
    def peaks_and_valleys(smooth_window: 10, prominence: 80.0)
      return [] if @points.size < smooth_window * 2

      raw_elevations = @points.map(&:elevation)
      smoothed       = smooth(raw_elevations, smooth_window)
      candidates     = slope_reversals(smoothed)

      candidates
        .select { |c| prominent_enough?(c, candidates, smoothed, prominence) }
        .map    { |c| build_feature(c, @points[c[:index]]) }
    end

    private

    def compute_statistics
      return nil if @points.empty?

      elevations = @points.map(&:elevation)
      n          = elevations.size
      mean       = elevations.sum / n.to_f
      variance   = elevations.sum { |e| (e - mean)**2 } / n.to_f
      stddev     = Math.sqrt(variance)
      sorted     = elevations.sort
      q1         = percentile(sorted, 25)
      median     = percentile(sorted, 50)
      q3         = percentile(sorted, 75)
      iqr        = q3 - q1

      {
        count: n,
        min: sorted.first,
        max: sorted.last,
        mean: mean.round(1),
        stddev: stddev.round(1),
        q1: q1.round(1),
        median: median.round(1),
        q3: q3.round(1),
        iqr: iqr.round(1),
        cv_pct: mean > 0 ? ((stddev / mean) * 100).round(1) : nil,
        terrain_class: classify_terrain(stddev, iqr)
      }
    end

    # Linear-interpolation percentile on a pre-sorted array.
    def percentile(sorted, pct)
      return sorted.first if pct <= 0
      return sorted.last  if pct >= 100

      rank  = (pct / 100.0) * (sorted.size - 1)
      lower = sorted[rank.floor]
      upper = sorted[rank.ceil]
      lower + (upper - lower) * (rank - rank.floor)
    end

    # Centred moving average — reduces noise without shifting peaks in time.
    def smooth(values, window)
      half = window / 2
      values.each_with_index.map do |_, i|
        lo = [i - half, 0].max
        hi = [i + half, values.size - 1].min
        values[lo..hi].sum / (hi - lo + 1).to_f
      end
    end

    # Finds indices where the slope changes sign (peaks and valleys).
    def slope_reversals(smoothed)
      candidates = []

      (1...smoothed.size - 1).each do |i|
        prev_slope = smoothed[i]     - smoothed[i - 1]
        next_slope = smoothed[i + 1] - smoothed[i]

        if    prev_slope > 0 && next_slope < 0 then candidates << { type: :peak,   index: i }
        elsif prev_slope < 0 && next_slope > 0 then candidates << { type: :valley, index: i }
        end
      end

      candidates
    end

    # Returns true when a candidate clears the prominence threshold against
    # its nearest flanking features of the opposite type.
    def prominent_enough?(candidate, all_candidates, smoothed, threshold)
      i    = candidate[:index]
      type = candidate[:type]

      left_opp  = all_candidates.select { |c| c[:type] != type && c[:index] < i }.last
      right_opp = all_candidates.select { |c| c[:type] != type && c[:index] > i }.first

      ref_left  = left_opp  ? smoothed[left_opp[:index]]  : smoothed.first
      ref_right = right_opp ? smoothed[right_opp[:index]] : smoothed.last

      case type
      when :peak   then smoothed[i] - [ref_left, ref_right].max >= threshold
      when :valley then [ref_left, ref_right].min - smoothed[i] >= threshold
      end
    end

    def build_feature(candidate, point)
      {
        type: candidate[:type],
        index: candidate[:index],
        latitude: point.latitude,
        longitude: point.longitude,
        elevation: point.elevation,
        distance: point.distance
      }
    end
  end
end
