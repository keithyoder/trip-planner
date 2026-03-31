// MapManager - A reusable class for managing Leaflet maps
import L from "leaflet"
import { WaypointIcons } from "./waypoint_icons";

// Surface category colours — used for colour-coded route polylines.
// Must stay in sync with Routes::SurfaceProfile::SURFACE_CATEGORIES in surface_profile.rb.
const SURFACE_CATEGORY_COLORS = {
  paved:       '#3388ff',  // blue       — asphalt, concrete, metal
  cobblestone: '#9c6b00',  // dark gold  — cobblestone, paving_stones, sett
  unpaved:     '#e07800',  // amber      — gravel, dirt, sand, grass …
  water:       '#00aacc',  // teal       — ferry crossings
  hiking:      '#7b2d8b',  // purple     — foot-hiking legs
  rail:        '#e53935',  // red        — train, metro, tram
  bus:         '#f57c00',  // orange     — bus, trolleybus
  unknown:     '#888888',  // grey
};

// Per-type colour overrides for surfaces that benefit from a distinct shade
// within their category. cobblestone/paving_stones/sett are handled by the
// :cobblestone category colour above and do not need entries here.
const SURFACE_TYPE_COLORS = {
  gravel:      '#cc5500',
  dirt:        '#8b5e3c',
  sand:        '#c2a000',
  ice:         '#aaddff',
  grass:       '#4caf50',
  grass_paver: '#4caf50',
  wood:        '#795548',
  woodchips:   '#795548',
};

/**
 * Returns the display colour for a surface segment.
 * Checks per-type overrides first, then falls back to category colour.
 * @param {string} surfaceType  e.g. "gravel", "sett"
 * @param {string} category     "paved" | "cobblestone" | "unpaved" | "water" | "hiking" | "unknown"
 */
function surfaceColor(surfaceType, category) {
  return SURFACE_TYPE_COLORS[surfaceType]
    || SURFACE_CATEGORY_COLORS[category]
    || SURFACE_CATEGORY_COLORS.unknown;
}

function createWaypointIcon(waypointType, size = 32) {
    const config = WaypointIcons[waypointType] || WaypointIcons.routing;

    const html = `
    <div class="waypoint-marker" style="
      width: ${size}px;
      height: ${size}px;
      background-color: ${config.backgroundColor};
      border: 3px solid ${config.color};
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
            // tileLayerUrl: 'https://tiles.stadiamaps.com/tiles/outdoors/{z}/{x}/{y}.png?api_key=50e54c7f-f220-44f9-875c-a0ce16bc63b5',
            // attribution: '&copy; <a href="https://stadiamaps.com/">Stadia Maps</a>, &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors'
            tileLayerUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            // tileLayerUrl: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
            // attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
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

    addWaypointMarker(lat, lon, waypointType, name = null, url = null) {
        const icon = createWaypointIcon(waypointType);
        const config = WaypointIcons[waypointType] || WaypointIcons.routing;
        let popupContent = null;

        if (name) {
            popupContent = `
        <div style="text-align: center;">
            <strong>${name}</strong><br>
            <small class="text-muted">${config.label}</small>
        </div>
        `;
        }

        const marker = this.addMarker(lat, lon, { icon: icon }, url ? null : popupContent);

        if (url) {
            marker.on('click', () => { window.location.href = url; });
        }

        return marker;
    }

    // Add a plain polyline to the map (single colour, no surface data)
    addPolyline(coordinates, options = {}) {
        const defaultOptions = {
            color: '#3388ff',
            weight: 4,
            opacity: 0.7
        };

        if (Array.isArray(coordinates[0][0])) {
            for (const segment of coordinates) {
                const polyline = L.polyline(segment, { ...defaultOptions, ...options }).addTo(this.map);
                this.polylines.push(polyline);
            }
        } else {
            const polyline = L.polyline(coordinates, { ...defaultOptions, ...options }).addTo(this.map);
            this.polylines.push(polyline);
        }
    }

    /**
     * Render a route as colour-coded polylines based on surface type.
     *
     * Each segment object must have:
     *   { surface_type: String, category: String, points: [[lat, lon], ...] }
     *
     * These map directly to the SurfaceSegment value objects produced by
     * Routes::SurfaceProfile#surface_segments (serialised to JSON).
     *
     * @param {Array}   segments     Array of surface segment objects
     * @param {Object}  options      Extra Leaflet polyline options (weight, opacity …)
     * @param {boolean} withTooltip  Show a tooltip with the surface type on hover
     */
    addSurfacePolylines(segments, options = {}, withTooltip = true) {
        if (!segments || segments.length === 0) return;

        for (const segment of segments) {
            const color = surfaceColor(segment.surface_type, segment.category);
            const label = (segment.surface_type || 'unknown').replace(/_/g, ' ');

            const polyline = L.polyline(segment.points, {
                color,
                weight:  options.weight  ?? 5,
                opacity: options.opacity ?? 0.85,
                ...options,
            }).addTo(this.map);

            if (withTooltip) {
                polyline.bindTooltip(
                    `<span style="text-transform:capitalize;">${label}</span>`,
                    { sticky: true, direction: 'top', offset: [0, -4] }
                );
            }

            this.polylines.push(polyline);
        }
    }

    /**
     * Add a surface legend control to the map.
     * Only shows categories that are actually present in the rendered segments,
     * so ferry-only or hiking-only routes don't clutter the legend.
     * Call after addSurfacePolylines.
     *
     * @param {Array} segments  The same segments array passed to addSurfacePolylines
     */
    addSurfaceLegend(segments = []) {
        // Collect only the categories present in this route
        const activeCategories = segments.length > 0
            ? [...new Set(segments.map(s => s.category))]
            : Object.keys(SURFACE_CATEGORY_COLORS);

        const LegendControl = L.Control.extend({
            options: { position: 'bottomright' },
            onAdd() {
                const div = L.DomUtil.create('div', 'leaflet-control leaflet-bar surface-legend');
                div.style.cssText = 'background:#fff;padding:8px 10px;font-size:12px;line-height:1.6;';
                div.innerHTML = activeCategories
                    .filter(cat => SURFACE_CATEGORY_COLORS[cat])
                    .map(cat =>
                        `<div>` +
                        `<span style="display:inline-block;width:14px;height:14px;border-radius:3px;` +
                        `background:${SURFACE_CATEGORY_COLORS[cat]};margin-right:6px;vertical-align:middle;"></span>` +
                        `<span style="text-transform:capitalize;">${cat}</span>` +
                        `</div>`
                    ).join('');
                return div;
            }
        });
        this.map.addControl(new LegendControl());
        return this;
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