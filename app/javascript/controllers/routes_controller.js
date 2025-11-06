import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import "leaflet-css"
import { createWaypointIcon, getWaypointConfig } from "./waypoint_icons"

// Connects to data-controller="routes"
export default class extends Controller {
  static targets = ["container"]
  static values = {
    waypoints: Array
  }

  connect() {
    console.log("Routes controller connected");
    
    // Fix Leaflet marker icon paths
    delete L.Icon.Default.prototype._getIconUrl;
    L.Icon.Default.mergeOptions({
      iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
      iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
      shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
    });
    
    // Get data attributes from the target element
    const lon = parseFloat(this.containerTarget.dataset.lon)
    const lat = parseFloat(this.containerTarget.dataset.lat)
    const routeData = this.containerTarget.dataset.route
    
    console.log("Map center:", { lat, lon });
    console.log("Route data (first 200 chars):", routeData ? routeData.substring(0, 200) : "null");
    
    // Initialize the map and store it as an instance variable
    this.map = L.map(this.containerTarget).setView([lat, lon], 6);
    
    // Store original bounds (will be set after route is displayed)
    this.originalBounds = null;

    // Add tile layer
    L.tileLayer('https://tiles.stadiamaps.com/tiles/outdoors/{z}/{x}/{y}.png?api_key=50e54c7f-f220-44f9-875c-a0ce16bc63b5', {
      maxZoom: 20,
      attribution: '&copy; <a href="https://stadiamaps.com/">Stadia Maps</a>, &copy; <a href="https://openmaptiles.org/">OpenMapTiles</a> &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors'
    }).addTo(this.map);

    // Add custom reset view control
    this.addResetViewControl();
    
    console.log("Map initialized");

    const directionsController = document.querySelector('[data-controller="directions"]');
    if (directionsController) {
      directionsController.map = this.map;
    }
    
    // If route data exists, parse and display it
    if (routeData && routeData.trim() !== '' && routeData !== 'null' && routeData !== 'undefined') {
      console.log("Attempting to display route...");
      this.displayRoute(routeData);
    } else {
      console.warn("No route data available");
    }
    
    // Display waypoints if available
    if (this.hasWaypointsValue && this.waypointsValue.length > 0) {
      console.log(`Displaying ${this.waypointsValue.length} waypoints`);
      this.displayWaypoints();
    }
  }

  displayRoute(routeData) {
    try {
      // If it's GeoJSON:
      if (routeData.startsWith('{')) {
        console.log("Parsing as GeoJSON");
        const geoJSON = JSON.parse(routeData);
        
        const layer = L.geoJSON(geoJSON, {
          style: {
            color: '#0066ff',
            weight: 4,
            opacity: 0.7
          }
        }).addTo(this.map);
        
        this.map.fitBounds(layer.getBounds());
        this.originalBounds = layer.getBounds();
        console.log("GeoJSON route displayed");
      }
      // If it's WKT MULTILINESTRING format
      else if (routeData.includes('MULTILINESTRING')) {
        console.log("Parsing as WKT MULTILINESTRING");
        const allCoords = this.parseWKTMultiLineString(routeData);
        console.log("Parsed line segments:", allCoords.length);
        
        if (allCoords.length > 0) {
          const bounds = L.latLngBounds([]);
          
          // Add each line segment
          allCoords.forEach((coords, index) => {
            if (coords.length > 0) {
              L.polyline(coords, {
                color: '#0066ff',
                weight: 4,
                opacity: 0.7
              }).addTo(this.map);
              
              // Extend bounds with this segment
              coords.forEach(coord => bounds.extend(coord));
              
              console.log(`Segment ${index + 1}: ${coords.length} points`);
            }
          });
          
          // Fit map to show all segments
          if (bounds.isValid()) {
            this.map.fitBounds(bounds);
            this.originalBounds = bounds;
            console.log("Map fitted to route bounds");
          }
        }
      }
      // If it's WKT LINESTRING format
      else if (routeData.includes('LINESTRING')) {
        console.log("Parsing as WKT LINESTRING");
        const coords = this.parseWKTLineString(routeData);
        
        if (coords.length > 0) {
          const polyline = L.polyline(coords, {
            color: '#0066ff',
            weight: 4,
            opacity: 0.7
          }).addTo(this.map);
          
          this.map.fitBounds(polyline.getBounds());
          this.originalBounds = polyline.getBounds();
          
          console.log("LINESTRING route displayed");
        }
      }
      else {
        console.error("Unknown route format");
      }
    } catch (error) {
      console.error('Error displaying route:', error);
    }
  }

  displayWaypoints() {
    // Display waypoints with custom icons
    this.waypointsValue.forEach((waypoint, index) => {
      const lat = waypoint.lat;
      const lon = waypoint.lon;
      const type = waypoint.type;
      const name = waypoint.name || `Waypoint ${index + 1}`;
      const sequence = waypoint.sequence;
      
      // Create custom icon for waypoint type
      const icon = createWaypointIcon(type, 36);
      const config = getWaypointConfig(type);
      
      const marker = L.marker([lat, lon], { 
        icon: icon,
        zIndexOffset: 1000 // Place waypoints above route
      }).addTo(this.map);
      
      // Build popup content
      let popupContent = `
        <div style="text-align: center; min-width: 150px;">
          <div style="background-color: ${config.backgroundColor}; padding: 8px; border-radius: 5px; margin-bottom: 8px;">
            <i class="bi ${config.icon}" style="color: ${config.color}; font-size: 1.2em;"></i>
            <strong style="margin-left: 8px; color: ${config.color};">Seq. ${sequence}</strong>
          </div>
          <strong style="font-size: 1.1em;">${name}</strong><br>
          <small class="text-muted">${config.label}</small>
      `;
      
      // Add toll information if present
      if (waypoint.toll && waypoint.toll > 0) {
        popupContent += `<br><small><i class="bi bi-cash"></i> ${waypoint.toll_formatted}</small>`;
      }
      
      // Add distance information if present
      if (waypoint.segment_distance) {
        popupContent += `<br><small><i class="bi bi-signpost-split"></i> ${waypoint.segment_distance}</small>`;
      }
      
      popupContent += `</div>`;
      
      marker.bindPopup(popupContent);
      
      // Extend bounds to include waypoint if we have route bounds
      if (this.originalBounds) {
        this.originalBounds.extend([lat, lon]);
      }
    });
  }

  parseWKTMultiLineString(wkt) {
    try {
      // Remove SRID prefix if present
      const cleanWkt = wkt.replace(/^SRID=\d+;/, '');
      
      // Match all coordinate groups within parentheses
      // MULTILINESTRING ((coords), (coords))
      const segmentMatches = cleanWkt.matchAll(/\(([^()]+)\)/g);
      const segments = Array.from(segmentMatches);
      
      console.log(`Found ${segments.length} segments in MULTILINESTRING`);
      
      return segments.map((match) => {
        const coordsString = match[1];
        
        return coordsString.split(',').map(pair => {
          const parts = pair.trim().split(/\s+/).filter(p => p);
          
          if (parts.length < 2) return null;
          
          const lon = parseFloat(parts[0]);
          const lat = parseFloat(parts[1]);
          // parts[2] is elevation - ignored
          
          if (isNaN(lon) || isNaN(lat)) return null;
          
          return [lat, lon]; // Leaflet uses [lat, lon] order
        }).filter(coord => coord !== null);
      }).filter(segment => segment.length > 0);
    } catch (error) {
      console.error("Error parsing MULTILINESTRING:", error);
      return [];
    }
  }

  parseWKTLineString(wkt) {
    try {
      const cleanWkt = wkt.replace(/^SRID=\d+;/, '');
      const coordsString = cleanWkt.match(/\(([^)]+)\)/);
      
      if (!coordsString) return [];
      
      return coordsString[1].split(',').map(pair => {
        const parts = pair.trim().split(/\s+/).filter(p => p);
        if (parts.length < 2) return null;
        
        const lon = parseFloat(parts[0]);
        const lat = parseFloat(parts[1]);
        
        if (isNaN(lon) || isNaN(lat)) return null;
        
        return [lat, lon];
      }).filter(coord => coord !== null);
    } catch (error) {
      console.error("Error parsing LINESTRING:", error);
      return [];
    }
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
      this.map.fitBounds(this.originalBounds, { padding: [50, 50] });
      console.log("View reset to original bounds");
    } else {
      console.warn("No original bounds saved");
    }
  }

  disconnect() {
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }
}