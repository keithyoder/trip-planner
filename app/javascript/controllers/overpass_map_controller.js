// app/javascript/controllers/overpass_map_controller.js
import { Controller } from "@hotwired/stimulus"
import { MapManager } from "../utils/map_manager"
import L from "leaflet"  // ← Add this import

export default class extends Controller {
  static values = {
    route: Array,
    pois: Array,
    nodeType: String,
    routeId: Number,
    importUrl: String
  }

  connect() {
    this.mapManager = new MapManager('map');
    this.markers = {};
    
    this.initializeMap();
    this.addPOIMarkers();
  }

  initializeMap() {
    // Add route as polyline
    this.mapManager.addPolyline(this.routeValue, {
      color: '#3388ff',
      weight: 4,
      opacity: 0.7
    });
    
    // Fit map to show the route
    this.mapManager.fitPolylineBounds();
  }

  addPOIMarkers() {
    this.poisValue.forEach(poi => {
      if (poi.lat && poi.lon) {
        const popupContent = this.createPopupContent(poi);
        const icon = this.createPoiIcon(this.nodeTypeValue);  // ← Create icon properly
        
        // Use addMarker with Leaflet icon object
        const marker = this.mapManager.addMarker(
          poi.lat, 
          poi.lon, 
          { icon: icon },  // ← Pass the icon object, not HTML string
          popupContent
        );
        
        this.markers[poi.osm_id] = marker;
      }
    });
  }

  createPoiIcon(nodeType) {
    const icons = {
      fuel: 'fuel-pump',
      toll: 'cash-coin',
      border_crossing: 'signpost-split',
      ferry: 'ferry',
      restaurant: 'cup-straw',
      bank: 'bank',
      hotel: 'building',
      parking: 'p-square',
      park: 'tree',
      rest_area: 'pause-circle'
    };
    const iconName = icons[nodeType] || 'geo-alt';
    const iconHtml = `<i class="bi bi-${iconName} fs-4 text-danger"></i>`;
    
    return L.divIcon({
      html: iconHtml,
      className: 'custom-poi-marker',
      iconSize: [30, 30],
      iconAnchor: [15, 15]
    });
  }

  createPopupContent(poi) {
    let html = `<div class="popup-content">
      <strong>${this.escapeHtml(poi.name || 'Unnamed')}</strong><br>`;
    
    if (poi.street) {
      html += `${this.escapeHtml(poi.street)}<br>`;
    }
    
    if (this.nodeTypeValue === 'toll') {
      if (poi.toll_amount) {
        html += `<span class="badge bg-success mt-1">${this.escapeHtml(poi.toll_amount)}</span><br>`;
      }
      if (poi.operator) {
        html += `<small class="text-muted">Operator: ${this.escapeHtml(poi.operator)}</small><br>`;
      }
    }
    
    html += `<button class="btn btn-sm btn-primary mt-2" 
                     data-osm-id="${poi.osm_id}"
                     data-action="click->overpass-map#importWaypoint">
               Import
             </button></div>`;
    
    return html;
  }

  panToMarker(event) {
    const item = event.currentTarget;
    
    // Don't pan if clicking the import button
    if (event.target.closest('.btn')) {
      return;
    }
    
    const poiId = item.dataset.poiId;
    const lat = parseFloat(item.dataset.lat);
    const lon = parseFloat(item.dataset.lon);
    
    if (this.markers[poiId]) {
      this.mapManager.map.setView([lat, lon], 15);
      this.markers[poiId].openPopup();
    }
  }

  importWaypoint(event) {
    event.stopPropagation();
    
    const btn = event.currentTarget;
    const osmId = btn.dataset.osmId;
    
    if (!confirm('Import this waypoint?')) return;
    
    btn.disabled = true;
    btn.textContent = 'Importing...';
    
    fetch(this.importUrlValue, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({ osm_id: osmId })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        btn.textContent = 'Imported ✓';
        btn.classList.remove('btn-primary');
        btn.classList.add('btn-success');
        this.showAlert(data.message, 'success');
      } else {
        btn.disabled = false;
        btn.textContent = 'Import';
        this.showAlert('Error: ' + data.message, 'danger');
      }
    })
    .catch(error => {
      btn.disabled = false;
      btn.textContent = 'Import';
      this.showAlert('Error importing waypoint', 'danger');
      console.error(error);
    });
  }

  showAlert(message, type) {
    const alert = document.createElement('div');
    alert.className = `alert alert-${type} alert-dismissible fade show position-fixed top-0 start-50 translate-middle-x mt-3`;
    alert.style.zIndex = '9999';
    alert.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `;
    document.body.appendChild(alert);
    setTimeout(() => alert.remove(), 3000);
  }

  escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  disconnect() {
    if (this.mapManager) {
      this.mapManager.destroy();
    }
  }
}