# frozen_string_literal: true

module Routing
  # Carries raw routing response data for a single profile leg before merging.
  #
  # Used by OrsService (driving/walking legs) and GoogleMapsService (transit
  # legs) to return a common structure that MergeService can combine regardless
  # of the source API.
  #
  # surfaces_summary is intentionally excluded — MergeService calculates it
  # from the promoted values array for accuracy and consistency.
  #
  # @param profile         [String]  ORS profile or 'transit'
  # @param coordinates     [Array]   [[lon, lat, ele], ...] — ele may be 0 for transit
  # @param segments        [Array]   ORS-style segment hashes with :steps, :distance, :duration
  # @param surfaces_values [Array]   [[start_idx, end_idx, code], ...] — empty for transit
  LegResult = Data.define(
    :profile,
    :coordinates,
    :segments,
    :surfaces_values
  )
end
