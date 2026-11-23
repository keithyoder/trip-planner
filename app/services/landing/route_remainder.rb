# frozen_string_literal: true

module Landing
  # The part of the planned route still ahead of the car, in map coordinates.
  #
  # Given the planned legs (arrays of [x, y]) and the car's position, find the
  # planned vertex nearest the car and return the route from there onward. Pure
  # geometry: no database.
  class RouteRemainder
    # Map pixels. Vertices within this much of the nearest one count as "equally
    # near". The route passes some places twice (it loops back through Rio
    # Gallegos and ends at home), and then the share already driven decides
    # which pass the car is on.
    TIE_DISTANCE = 4.0

    def self.after(legs, position:, fraction:)
      new(legs, position, fraction).call
    end

    def initialize(legs, position, fraction)
      @legs = legs
      @position = position
      @fraction = fraction
    end

    # @return [Array<Array<Array(Float, Float)>>] legs; the first starts at the
    #   car's vertex, the rest are untouched.
    def call
      return @legs if @legs.empty?

      best = nearest_vertex
      [@legs[best[:leg]][best[:vertex]..]] + @legs[(best[:leg] + 1)..]
    end

    private

    # Position wins: the car is at the vertex nearest to it. The share driven is
    # only a tiebreaker, because it can drift from the plan (detours make the
    # odometer run ahead of the planned length) while the position cannot.
    def nearest_vertex
      candidates = vertices_with_progress.each { |v| v[:gap] = gap(v) }
      closest = candidates.map { |v| v[:gap] }.min
      equally_near = candidates.select { |v| v[:gap] <= closest + TIE_DISTANCE }
      equally_near.min_by { |v| (v[:progress] - @fraction).abs }
    end

    def gap(vertex)
      Math.sqrt(squared_distance(vertex[:point], @position))
    end

    # Every vertex with how far along the route it is (0..1), measured in map
    # space, which only needs to grow along the route.
    def vertices_with_progress
      steps = @legs.flat_map.with_index { |points, leg| leg_vertices(points, leg) }
      total = steps.sum { |v| v[:step] }
      run = 0.0
      steps.map do |v|
        run += v[:step]
        v.merge(progress: total.positive? ? run / total : 0.0)
      end
    end

    def leg_vertices(points, leg)
      points.each_index.map do |vertex|
        { leg: leg, vertex: vertex, point: points[vertex], step: step(points, vertex) }
      end
    end

    # Distance from the previous vertex of the same leg (0 for a leg's first).
    def step(points, vertex)
      vertex.zero? ? 0.0 : Math.sqrt(squared_distance(points[vertex], points[vertex - 1]))
    end

    def squared_distance(from, to)
      ((from[0] - to[0])**2) + ((from[1] - to[1])**2)
    end
  end
end
