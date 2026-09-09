import { Controller } from "@hotwired/stimulus"
import "leaflet-css"
import L from "leaflet"
import { MapManager } from "../utils/map_manager"

export default class extends Controller {
  static targets = ["container"]

  connect() {
    const tripLogs = JSON.parse(this.containerTarget.dataset.tripLogs || '[]')
    const stops = JSON.parse(this.containerTarget.dataset.stops || '[]')

    this.mapManager = new MapManager(this.containerTarget, { center: [0, 0], zoom: 12 })

    if (tripLogs.length === 0) {
      console.warn("No trip logs for this day")
    } else {
      const colors = ['#3388ff', '#e07800', '#7b2d8b', '#00aacc', '#e53935']
      tripLogs.forEach((tripLog, i) => {
        this.mapManager.addPolyline(tripLog.coordinates, { color: colors[i % colors.length], weight: 4, opacity: 0.8 })
      })
    }

    stops.forEach(stop => {
      const marker = this.mapManager.addWaypointMarker(stop.lat, stop.lon, stop.stop_type, stop.name)
      marker.bindPopup(`
        <div style="text-align: center;">
          <strong>${stop.name}</strong><br>
          <small class="text-muted">${stop.duration_minutes} min</small><br>
          <a href="${stop.edit_url}">Edit</a>
        </div>
      `)
    })

    this.mapManager.fitPolylineBounds()
  }

  disconnect() {
    this.mapManager?.destroy()
  }
}