// MapManager - A reusable class for managing Leaflet maps
import L from "leaflet"

const WaypointIcons = {
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

function createWaypointIcon(waypointType, size = 32) {
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

export class MapManager {
    constructor(container, options = {}) {
        // Default configuration
        const defaults = {
            center: [0, 0],
            zoom: 14,
            maxZoom: 19,
            tileLayerUrl: 'https://tiles.stadiamaps.com/tiles/outdoors/{z}/{x}/{y}.png?api_key=50e54c7f-f220-44f9-875c-a0ce16bc63b5',
            attribution: '&copy; <a href="https://stadiamaps.com/">Stadia Maps</a>, &copy; <a href="https://openmaptiles.org/">OpenMapTiles</a> &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors'
        };

        // Merge options with defaults
        this.config = { ...defaults, ...options };

        // Store container reference
        this.container = container;

        // Initialize map
        this.map = null;
        this.markers = [];
        this.polylines = [];

        this.initialize();
    }

    initialize() {
        delete L.Icon.Default.prototype._getIconUrl;
        L.Icon.Default.mergeOptions({
            iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
            iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
            shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
        });

        // Create the map
        this.map = L.map(this.container, { zoomSnap: 0.1 }).setView(
            this.config.center,
            this.config.zoom
        );

        // Add tile layer
        L.tileLayer(this.config.tileLayerUrl, {
            maxZoom: this.config.maxZoom,
            attribution: this.config.attribution
        }).addTo(this.map);

        this.addResetViewControl();

        return this;
    }

    // Set the map view to specific coordinates
    setView(lat, lon, zoom = null) {
        const zoomLevel = zoom || this.config.zoom;
        this.map.setView([lat, lon], zoomLevel);
        return this;
    }

    // Add a marker to the map
    addMarker(lat, lon, options = {}, popupContent = null) {
        const marker = L.marker([lat, lon], options).addTo(this.map);
        this.markers.push(marker);
        if (popupContent) {
            marker.bindPopup(popupContent);
        }
        return marker;
    }

    addWaypointMarker(lat, lon, waypointType, name = null) {
        const icon = createWaypointIcon(waypointType);
        const config = WaypointIcons[waypointType] || WaypointIcons.routing;
        let popupContent = null;

        // Add popup with waypoint information
        if (name) {
            popupContent = `
        <div style="text-align: center;">
          <strong>${name}</strong><br>
          <small class="text-muted">${config.label}</small>
        </div>
      `;
        }

        return this.addMarker(lat, lon, { icon: icon }, popupContent)
    }

    // Add a polyline to the map
    addPolyline(coordinates, options = {}) {
        const defaultOptions = {
            color: '#3388ff',
            weight: 4,
            opacity: 0.7
        };

        const polyline = L.polyline(coordinates, { ...defaultOptions, ...options }).addTo(this.map);
        this.polylines.push(polyline);
        return polyline;
    }

    // Fit map bounds to show all markers
    fitMarkerBounds(padding = [50, 50]) {
        if (this.markers.length === 0) return this;

        const group = L.featureGroup(this.markers);
        this.map.fitBounds(group.getBounds().pad(0.1), { padding });
        this.originalBounds = group.getBounds();
        return this;
    }

    // Fit map bounds to show all polylines
    fitPolylineBounds(padding = [50, 50]) {
        if (this.polylines.length === 0) return this;

        const group = L.featureGroup(this.polylines);
        this.map.fitBounds(group.getBounds().pad(0.1), { padding });
        this.originalBounds = group.getBounds();
        return this;
    }

    // Fit map to show all markers and polylines
    fitAllBounds(padding = [50, 50]) {
        const allLayers = [...this.markers, ...this.polylines];
        if (allLayers.length === 0) return this;

        const group = L.featureGroup(allLayers);
        this.map.fitBounds(group.getBounds().pad(0.1), { padding, maxZoom: this.config.zoom });
        this.originalBounds = group.getBounds();
        return this;
    }

    addResetViewControl() {
        // Create a custom Leaflet control for the reset button
        const ResetControl = L.Control.extend({
            options: {
                position: 'topleft'
            },

            onAdd: (map) => {
                const container = L.DomUtil.create('div', 'leaflet-bar leaflet-control leaflet-control-custom');

                const link = L.DomUtil.create('a', '', container);
                link.href = '#';
                link.title = 'Reset view to show entire route';
                link.setAttribute('role', 'button');
                link.setAttribute('aria-label', 'Reset view');
                link.innerHTML = '<i class="bi bi-arrow-clockwise"></i>';

                link.onclick = (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    this.resetView();
                };

                // Prevent map drag when clicking the button
                L.DomEvent.disableClickPropagation(container);

                return container;
            }
        });

        this.map.addControl(new ResetControl());
    }

    resetView() {
        if (this.originalBounds) {
            this.map.fitBounds(this.originalBounds, { padding: [50, 50], maxZoom: this.config.zoom });
            console.log("View reset to original bounds");
        } else {
            console.warn("No original bounds saved");
        }
    }

    // Clear all markers
    clearMarkers() {
        this.markers.forEach(marker => marker.remove());
        this.markers = [];
        return this;
    }

    // Clear all polylines
    clearPolylines() {
        this.polylines.forEach(polyline => polyline.remove());
        this.polylines = [];
        return this;
    }

    // Clear all markers and polylines
    clearAll() {
        this.clearMarkers();
        this.clearPolylines();
        return this;
    }

    // Get the underlying Leaflet map instance
    getMap() {
        return this.map;
    }

    // Destroy the map
    destroy() {
        if (this.map) {
            this.clearAll();
            this.map.remove();
            this.map = null;
        }
    }
}