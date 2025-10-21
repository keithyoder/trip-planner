class SegmentSurface
  SURFACE_TYPES = {
    unknown: 0,
    paved: 1,
    unpaved: 2,
    asphalt: 3,
    concrete: 4,
    cobblestone: 5,
    metal: 6,
    wood: 7,
    compacted_gravel: 8,
    fine_gravel: 9,
    gravel: 10,
    dirt: 11,
    ground: 12,
    ice: 13,
    paving_stones: 14,
    sand: 15,
    woodchips: 16,
    grass: 17,
    grass_paver: 18
  }.freeze

  def initialize(value, route)
    @beginning = value[0]
    @end = value[1]
    @surface_type = value[2]
    @route = route
  end

  def distance
    @route.distance_between_points(@beginning, @end)
  end

  def surface_type
    SURFACE_TYPES.key?(@surface_type) ? SURFACE_TYPES.key(@surface_type) : :other
  end
end