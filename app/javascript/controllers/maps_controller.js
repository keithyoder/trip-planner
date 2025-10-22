import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import "leaflet-css"

// Connects to data-controller="maps"
export default class extends Controller {
  static targets = ["container"]

  connect() {
    // Get data attributes from the target element
    const lon = parseFloat(this.containerTarget.dataset.lon)
    const lat = parseFloat(this.containerTarget.dataset.lat)
    
    // Initialize the map and store it as an instance variable
    this.map = L.map(this.containerTarget).setView([lat, lon], 14);

    // Add tile layer
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(this.map);
    
    // Optional: Add a marker at the center
    // L.marker([lat, lon]).addTo(this.map);
  }

  disconnect() {
    // Clean up the map when the controller disconnects
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }
}
