import { Controller } from "@hotwired/stimulus"
import "leaflet-css"
import { MapManager } from "../utils/map_manager"


// Connects to data-controller="routes"
export default class extends Controller {
  static targets = ["container"]
  static values = {
    waypoints: Array
  }

  connect() {
    console.log("Routes controller connected");
    
    // Get data attributes from the target element
    const lon = parseFloat(this.containerTarget.dataset.lon)
    const lat = parseFloat(this.containerTarget.dataset.lat)
    const routeData = this.containerTarget.dataset.route
        
    this.mapManager = new MapManager(this.containerTarget, {
      center: [lat, lon],
      zoom: 17
    });

    const directionsController = document.querySelector('[data-controller="directions"]');
    if (directionsController) {
      directionsController.map = this.map;
    }
    
    // If route data exists, parse and display it
    if (routeData && routeData.trim() !== '' && routeData !== 'null' && routeData !== 'undefined') {
      this.mapManager.addPolyline(JSON.parse(routeData));
    } else {
      console.warn("No route data available");
    }
    
    // Display waypoints if available
    if (this.hasWaypointsValue && this.waypointsValue.length > 0) {
      console.log(`Displaying ${this.waypointsValue.length} waypoints`);
      this.displayWaypoints();
    }

    this.mapManager.fitAllBounds([0,0]);
  }

  displayWaypoints() {
    // Display waypoints with custom icons
    this.waypointsValue.forEach((waypoint, index) => {
      const lat = waypoint.lat;
      const lon = waypoint.lon;
      const type = waypoint.type;
      const name = waypoint.name || `Waypoint ${index + 1}`;
      const sequence = waypoint.sequence;
      
      this.mapManager.addWaypointMarker(lat, lon, type, name);

    });
  }

  disconnect() {
    if (this.mapManager) {
      this.mapManager.destroy();
    }
  }
}