# frozen_string_literal: true

module OverpassHelper
  def poi_icon(node_type)
    icons = {
      fuel: 'fuel-pump',
      toll: 'cash-coin',
      border_crossing: 'signpost-split',
      ferry: 'ferry',
      restaurant: 'cup-straw',
      bank: 'bank',
      hotel: 'building',
      parking: 'p-square',
      park: 'tree',
      rest_area: 'pause-circle'
    }
    icons[node_type] || 'geo-alt'
  end
end
