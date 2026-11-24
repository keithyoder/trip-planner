import { Controller } from "@hotwired/stimulus"
import "leaflet-css"
import L from "leaflet"

// The map on the read-only day pages: the planned line (ink, with a white edge)
// and numbered stop markers on light street tiles. Touch devices pan with one finger
// and pinch to zoom; the page scroll is never captured by the wheel.
export default class extends Controller {
  static values = { line: Array, stops: Array }

  connect() {
    this.map = L.map(this.element, { zoomControl: false, attributionControl: false, scrollWheelZoom: false, zoomSnap: 0.1 })
    // No "Leaflet" prefix: it is a courtesy, not a requirement, and the line has to fit a phone.
    L.control.attribution({ prefix: false }).addTo(this.map)
    L.tileLayer("https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png?api_key=50e54c7f-f220-44f9-875c-a0ce16bc63b5", {
      maxZoom: 19,
      // Stadia's tiles need all three credits. One © covers the list, and OpenStreetMap's short form
      // (without "contributors") is allowed where space is tight, as long as it links to the copyright page.
      attribution: '&copy; <a href="https://stadiamaps.com/">Stadia Maps</a> <a href="https://openmaptiles.org/">OpenMapTiles</a> <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(this.map)
    L.control.zoom({ position: "topright", zoomInTitle: "+", zoomOutTitle: "−" }).addTo(this.map)

    // A light map hides a pale dotted line, so the route is a solid ink line with a white edge: it reads
    // on roads, water and parks alike.
    L.polyline(this.lineValue, { color: "#ffffff", weight: 9, opacity: 0.9, lineCap: "round", lineJoin: "round" }).addTo(this.map)
    const line = L.polyline(this.lineValue, { color: "#141414", weight: 4, lineCap: "round", lineJoin: "round" }).addTo(this.map)
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
