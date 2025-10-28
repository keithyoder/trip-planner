import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import "leaflet-css"

// Connects to data-controller="routes"
export default class extends Controller {
  static targets = ["container"]

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
    
    // If route data exists, parse and display it
    if (routeData && routeData.trim() !== '' && routeData !== 'null' && routeData !== 'undefined') {
      console.log("Attempting to display route...");
      this.displayRoute(routeData);
    } else {
      console.warn("No route data available");
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
            this.originalBounds = bounds; // Save original bounds
            console.log("Map fitted to route bounds");
          }
          
          // Add start and end markers
          const firstSegment = allCoords[0];
          const lastSegment = allCoords[allCoords.length - 1];
          if (firstSegment.length > 0 && lastSegment.length > 0) {
            L.marker(firstSegment[0])
              .addTo(this.map)
              .bindPopup('Start');
            L.marker(lastSegment[lastSegment.length - 1])
              .addTo(this.map)
              .bindPopup('End');
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
          this.originalBounds = polyline.getBounds(); // Save original bounds
          
          // Add markers
          L.marker(coords[0]).addTo(this.map).bindPopup('Start');
          L.marker(coords[coords.length - 1]).addTo(this.map).bindPopup('End');
          
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
      this.map.fitBounds(this.originalBounds);
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
