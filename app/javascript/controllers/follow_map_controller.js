import { Controller } from "@hotwired/stimulus"
import "leaflet-css"
import L from "leaflet"

// The map on the read-only day pages: the planned line (dotted, paper colour)
// and numbered stop markers on dark tiles. Touch devices pan with one finger
// and pinch to zoom; the page scroll is never captured by the wheel.
export default class extends Controller {
  static values = { line: Array, stops: Array }

  connect() {
    this.map = L.map(this.element, { zoomControl: false, scrollWheelZoom: false, zoomSnap: 0.1 })
    L.tileLayer("https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}.png?api_key=50e54c7f-f220-44f9-875c-a0ce16bc63b5", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://stadiamaps.com/">Stadia Maps</a>, &copy; <a href="https://openstreetmap.org">OpenStreetMap</a> contributors'
    }).addTo(this.map)
    L.control.zoom({ position: "topright", zoomInTitle: "+", zoomOutTitle: "−" }).addTo(this.map)

    const line = L.polyline(this.lineValue, { color: "#f4efe6", weight: 4, opacity: 0.95, dashArray: "2 9", lineCap: "round" }).addTo(this.map)
    this.stopsValue.forEach((stop) => {
      const icon = L.divIcon({
        className: "follow-stop",
        html: `<span>${stop.number}</span>`,
        iconSize: [28, 28],
        iconAnchor: [14, 14]
      })
      L.marker([stop.lat, stop.lon], { icon, title: stop.name }).addTo(this.map)
    })
    this.map.fitBounds(line.getBounds(), { padding: [30, 30] })
  }

  disconnect() {
    this.map?.remove()
  }
}
