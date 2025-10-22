import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import "leaflet-css"

// Connects to data-controller="routes"
export default class extends Controller {
  static targets = ["container"]

  connect() {
    // Get data attributes from the target element
    const lon = parseFloat(this.containerTarget.dataset.lon)
    const lat = parseFloat(this.containerTarget.dataset.lat)
    const routeData = this.containerTarget.dataset.route
    
    // Initialize the map and store it as an instance variable
    this.map = L.map(this.containerTarget).setView([lat, lon], 6);

    // Add tile layer
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(this.map);
    
    // If route data exists, parse and display it
    if (routeData && routeData.trim() !== '') {
      this.displayRoute(routeData);
    }
  }

  displayRoute(routeData) {
    try {
      // Parse the route geometry (assuming it's GeoJSON or WKT format)
      // Adjust this parsing based on your actual data format
      
      // If it's GeoJSON:
      if (routeData.startsWith('{')) {
        const geoJSON = JSON.parse(routeData);
        const layer = L.geoJSON(geoJSON, {
          style: {
            color: '#0066ff',
            weight: 4,
            opacity: 0.7
          }
        }).addTo(this.map);
        
        // Fit map bounds to the route
        this.map.fitBounds(layer.getBounds());
      } 
      // If it's WKT LineString format (e.g., "LINESTRING(lon lat, lon lat, ...)")
      else if (routeData.includes('LINESTRING')) {
        const coords = this.parseWKTLineString(routeData);
        if (coords.length > 0) {
          const polyline = L.polyline(coords, {
            color: '#0066ff',
            weight: 4,
            opacity: 0.7
          }).addTo(this.map);
          
          // Fit map bounds to the route
          this.map.fitBounds(polyline.getBounds());
          
          // Add start and end markers
          if (coords.length > 0) {
            L.marker(coords[0]).addTo(this.map).bindPopup('Start');
            L.marker(coords[coords.length - 1]).addTo(this.map).bindPopup('End');
          }
        }
      }
    } catch (error) {
      console.error('Error displaying route:', error);
    }
  }

  parseWKTLineString(wkt) {
    // Parse WKT LINESTRING format: "LINESTRING(lon lat, lon lat, ...)"
    const coordsString = wkt.match(/\(([^)]+)\)/);
    if (!coordsString) return [];
    
    return coordsString[1].split(',').map(pair => {
      const [lon, lat] = pair.trim().split(' ').map(parseFloat);
      return [lat, lon]; // Leaflet uses [lat, lon] order
    });
  }

  disconnect() {
    // Clean up the map when the controller disconnects
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }
}
