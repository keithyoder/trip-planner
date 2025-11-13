import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

export default class extends Controller {
  static targets = ["step"]
  
  connect() {
    this.currentMarker = null
  }
  
  get map() {
    // Check if map is attached to this element
    if (this.element.mapManager) {
      return this.element.mapManager.map
    }
  }

  showOnMap(event) {
    const row = event.currentTarget
    const lat = parseFloat(row.dataset.lat)
    const lng = parseFloat(row.dataset.lng)
    const instruction = row.dataset.instruction
    
    // Remove previous marker
    if (this.currentMarker) {
      this.map.removeLayer(this.currentMarker)
    }
    
    // Create new marker
    this.currentMarker = L.marker([lat, lng], {
      icon: L.icon({
        iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
        shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
        iconSize: [25, 41],
        iconAnchor: [12, 41],
        popupAnchor: [1, -34],
        shadowSize: [41, 41]
      })
    }).addTo(this.map)
    
    this.currentMarker.bindPopup(`<strong>${instruction}</strong>`).openPopup()
    this.map.setView([lat, lng], Math.max(this.map.getZoom(), 18), { animate: true, duration: 0.5 })
    
    // Highlight row
    this.stepTargets.forEach(r => r.classList.remove('table-info'))
    row.classList.add('table-info')
  }
}
