import { Controller } from "@hotwired/stimulus"
import "leaflet-css"
import { MapManager } from "../utils/map_manager"

// Connects to data-controller="maps"
export default class extends Controller {
  static targets = ["container"]
  static values = {
    waypoints: Array
  }

  connect() {
    // Get data attributes from the target element
    const lon = parseFloat(this.containerTarget.dataset.lon)
    const lat = parseFloat(this.containerTarget.dataset.lat)

    console.log("Maps controller connected:", { lat, lon });

    this.mapManager = new MapManager(this.containerTarget, {
      center: [lat, lon],
      zoom: 14
    });

    // Add waypoint marker if we have waypoint data
    const waypointType = this.containerTarget.dataset.waypointType;
    const waypointName = this.containerTarget.dataset.waypointName;

    if (waypointType) {
      this.mapManager.addWaypointMarker(lat, lon, waypointType, waypointName);
    } else {
      this.mapManager.addMarker(lat, lon);
    }
    this.mapManager.fitAllBounds();

    // If we have multiple waypoints, display them all
    if (this.hasWaypointsValue && this.waypointsValue.length > 0) {
      this.displayWaypoints();
    }
  }

  displayWaypoints() {
    // For displaying multiple waypoints (e.g., on a route or trip map)    
    this.waypointsValue.forEach((waypoint, index) => {
      const lat = waypoint.lat;
      const lon = waypoint.lon;
      const type = waypoint.type;
      const name = waypoint.name || `Waypoint ${index + 1}`;
      const sequence = waypoint.sequence;

      const marker = this.mapManager.addWaypointMarker(lat, lon, type, name);

      // Add sequence number to popup if available
      if (sequence) {
        //const config = getWaypointConfig(type);
        const popupContent = `
          <div style="text-align: center;">
            <div style="background-color: ${waypoint.backgroundColor}; padding: 5px; border-radius: 5px; margin-bottom: 5px;">
              <i class="bi ${waypoint.icon}" style="color: ${waypoint.color};"></i>
              <strong style="margin-left: 5px;">Seq. ${sequence}</strong>
            </div>
            <strong>${name}</strong><br>
            <small class="text-muted">${waypoint.label}</small>
          </div>
        `;
        marker.bindPopup(popupContent);
      }
    });

    this.mapManager.fitMarkerBounds();
  }

  disconnect() {
    // Clean up the map when the controller disconnects
    if (this.mapMapManager) {
      this.mapManager.destroy();
    }
  }
}