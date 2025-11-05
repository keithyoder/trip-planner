import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import "leaflet-css"
import { createWaypointIcon, getWaypointConfig } from "./waypoint_icons"

// Connects to data-controller="maps"
export default class extends Controller {
  static targets = ["container"]
  static values = {
    waypoints: Array
  }

  connect() {
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
    
    console.log("Maps controller connected:", { lat, lon });
    
    // Initialize the map and store it as an instance variable
    this.map = L.map(this.containerTarget).setView([lat, lon], 14);

    // Add tile layer
    L.tileLayer(
      'https://tiles.stadiamaps.com/tiles/outdoors/{z}/{x}/{y}.png?api_key=50e54c7f-f220-44f9-875c-a0ce16bc63b5',
      {
        maxZoom: 19,
        attribution: '&copy; <a href="https://stadiamaps.com/">Stadia Maps</a>, &copy; <a href="https://openmaptiles.org/">OpenMapTiles</a> &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors'
      }
    ).addTo(this.map);
    
    // Add waypoint marker if we have waypoint data
    const waypointType = this.containerTarget.dataset.waypointType;
    const waypointName = this.containerTarget.dataset.waypointName;
    
    if (waypointType) {
      this.addWaypointMarker(lat, lon, waypointType, waypointName);
    } else {
      // Default marker for single location without type
      L.marker([lat, lon]).addTo(this.map);
    }
    
    // If we have multiple waypoints, display them all
    if (this.hasWaypointsValue && this.waypointsValue.length > 0) {
      this.displayWaypoints();
    }
  }
  
  addWaypointMarker(lat, lon, waypointType, name = null) {
    const icon = createWaypointIcon(waypointType);
    const config = getWaypointConfig(waypointType);
    
    const marker = L.marker([lat, lon], { icon: icon }).addTo(this.map);
    
    // Add popup with waypoint information
    if (name) {
      const popupContent = `
        <div style="text-align: center;">
          <strong>${name}</strong><br>
          <small class="text-muted">${config.label}</small>
        </div>
      `;
      marker.bindPopup(popupContent);
    }
    
    return marker;
  }
  
  displayWaypoints() {
    // For displaying multiple waypoints (e.g., on a route or trip map)
    const bounds = L.latLngBounds([]);
    
    this.waypointsValue.forEach((waypoint, index) => {
      const lat = waypoint.lat;
      const lon = waypoint.lon;
      const type = waypoint.type;
      const name = waypoint.name || `Waypoint ${index + 1}`;
      const sequence = waypoint.sequence;
      
      const marker = this.addWaypointMarker(lat, lon, type, name);
      
      // Add sequence number to popup if available
      if (sequence) {
        const config = getWaypointConfig(type);
        const popupContent = `
          <div style="text-align: center;">
            <div style="background-color: ${config.backgroundColor}; padding: 5px; border-radius: 5px; margin-bottom: 5px;">
              <i class="bi ${config.icon}" style="color: ${config.color};"></i>
              <strong style="margin-left: 5px;">Seq. ${sequence}</strong>
            </div>
            <strong>${name}</strong><br>
            <small class="text-muted">${config.label}</small>
          </div>
        `;
        marker.bindPopup(popupContent);
      }
      
      bounds.extend([lat, lon]);
    });
    
    // Fit map to show all waypoints
    if (bounds.isValid()) {
      this.map.fitBounds(bounds, { padding: [50, 50] });
    }
  }

  disconnect() {
    // Clean up the map when the controller disconnects
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }
}