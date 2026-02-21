# frozen_string_literal: true

module Waypoints
  # Assigns administrative boundaries to waypoints using PostGIS spatial queries.
  #
  # Boundaries are stored in the boundaries_waypoints join table and represent
  # the administrative hierarchy containing each waypoint's coordinates —
  # country (level 2), state (level 4), municipality (level 6), etc.
  #
  # == Single waypoint assignment
  #
  # Assign all missing boundary levels to one waypoint:
  #
  #   Waypoints::BoundaryAssigner.new(waypoint).assign
  #
  # Assign a specific level only:
  #
  #   Waypoints::BoundaryAssigner.new(waypoint).assign_level(4)
  #
  # == Bulk assignment
  #
  # Assign a specific level across all waypoints that are missing it:
  #
  #   Waypoints::BoundaryAssigner.assign_missing(level: 4)
  #
  # Assign all levels across all waypoints missing any of them:
  #
  #   Waypoints::BoundaryAssigner.assign_missing
  #
  class BoundaryAssigner
    # Administrative boundary levels used in the South American context.
    # 2 = country, 4 = state/province, 6 = municipality
    LEVELS = [2, 4, 6, 7, 8].freeze

    # @param waypoint [Waypoint]
    def initialize(waypoint)
      @waypoint = waypoint
    end

    # Assigns boundaries at all standard levels that are not yet assigned.
    #
    # Skips any level where the waypoint already has a boundary, so this is
    # safe to call repeatedly without creating duplicates.
    #
    # @return [void]
    def assign
      LEVELS.each do |level|
        next if already_assigned?(level)

        assign_level(level)
      end
    end

    # Assigns the boundary at a specific administrative level.
    #
    # Does nothing if no containing boundary is found at that level —
    # this can happen legitimately for waypoints near borders or in
    # areas with incomplete OSM boundary data.
    #
    # @param level [Integer] administrative level (2, 4, 6, etc.)
    # @return [void]
    def assign_level(level)
      boundary = Boundary.select(:id).waypoint(@waypoint, level).first
      @waypoint.boundaries << boundary if boundary.present?
    end

    # Bulk-assigns boundaries at one or more levels across all waypoints
    # that are missing them.
    #
    # @param levels [Array<Integer>] defaults to LEVELS
    # @return [void]
    def self.assign_missing(levels: LEVELS)
      Array(levels).each do |level|
        Waypoint.no_level(level).find_each do |waypoint|
          new(waypoint).assign_level(level)
        end
      end
    end

    private

    # Returns true if this waypoint already has a boundary at the given level.
    # Uses the in-memory association if already loaded to avoid an extra query.
    #
    # @param level [Integer]
    # @return [Boolean]
    def already_assigned?(level)
      if @waypoint.boundaries.loaded?
        @waypoint.boundaries.any? { |b| b.level == level }
      else
        @waypoint.boundaries.where(level: level).exists?
      end
    end
  end
end
