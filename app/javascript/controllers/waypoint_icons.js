// Waypoint icon definitions using Bootstrap Icons
// Maps waypoint types to icon HTML and colors

export const WaypointIcons = {
  // Icon configurations for each waypoint type
  overnight: {
    icon: 'bi-moon-stars-fill',
    color: '#6f42c1', // purple
    backgroundColor: '#e7d9ff',
    label: 'Overnight'
  },
  lunch: {
    icon: 'bi-cup-hot-fill',
    color: '#fd7e14', // orange
    backgroundColor: '#ffe5d0',
    label: 'Lunch'
  },
  ferry_boarding: {
    icon: 'bi-water',
    color: '#0dcaf0', // cyan
    backgroundColor: '#cff4fc',
    label: 'Ferry Boarding'
  },
  ferry_disembarkment: {
    icon: 'bi-water',
    color: '#0d6efd', // blue
    backgroundColor: '#cfe2ff',
    label: 'Ferry Disembarkment'
  },
  toll_booth: {
    icon: 'bi-cash-coin',
    color: '#198754', // green
    backgroundColor: '#d1e7dd',
    label: 'Toll Booth'
  },
  border_crossing: {
    icon: 'bi-shield-check',
    color: '#dc3545', // red
    backgroundColor: '#f8d7da',
    label: 'Border Crossing'
  },
  gas_station: {
    icon: 'bi-fuel-pump-fill',
    color: '#ffc107', // yellow
    backgroundColor: '#fff3cd',
    label: 'Gas Station'
  },
  attraction: {
    icon: 'bi-camera-fill',
    color: '#d63384', // pink
    backgroundColor: '#f7d6e6',
    label: 'Attraction'
  },
  routing: {
    icon: 'bi-signpost-2-fill',
    color: '#6c757d', // gray
    backgroundColor: '#e9ecef',
    label: 'Routing'
  }
};

// Create a Leaflet DivIcon for a waypoint
export function createWaypointIcon(waypointType, size = 32) {
  const config = WaypointIcons[waypointType] || WaypointIcons.routing;
  
  const html = `
    <div class="waypoint-marker" style="
      width: ${size}px;
      height: ${size}px;
      background-color: ${config.backgroundColor};
      border: 3px solid ${config.color};
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 2px 5px rgba(0,0,0,0.3);
    ">
      <i class="bi ${config.icon}" style="
        font-size: ${size * 0.5}px;
        color: ${config.color};
      "></i>
    </div>
  `;
  
  return L.divIcon({
    html: html,
    className: 'waypoint-icon-container',
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    popupAnchor: [0, -size / 2]
  });
}

// Get configuration for a waypoint type
export function getWaypointConfig(waypointType) {
  return WaypointIcons[waypointType] || WaypointIcons.routing;
}