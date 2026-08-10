import { Controller } from "@hotwired/stimulus"
import "leaflet-css"
import L from "leaflet"
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
    const lon             = parseFloat(this.containerTarget.dataset.lon)
    const lat             = parseFloat(this.containerTarget.dataset.lat)
    const routeData       = this.containerTarget.dataset.route
    const surfaceData     = this.containerTarget.dataset.surfaceSegments
        
    this.mapManager = new MapManager(this.containerTarget, {
      center: [lat, lon],
      zoom: 17
    });

    const directionsController = document.querySelector('[data-controller="directions"]');
    if (directionsController) {
      directionsController.mapManager = this.mapManager;
    }
    
    // Prefer surface-coded polylines; fall back to a plain blue polyline
    if (surfaceData && surfaceData.trim() !== '' && surfaceData !== 'null') {
      const segments = JSON.parse(surfaceData);
      if (segments.length > 0) {
        this.mapManager.addSurfacePolylines(segments);
        this.mapManager.addSurfaceLegend(segments);
      } else if (routeData && routeData.trim() !== '' && routeData !== 'null' && routeData !== 'undefined') {
        this.mapManager.addPolyline(JSON.parse(routeData));
      }
    } else if (routeData && routeData.trim() !== '' && routeData !== 'null' && routeData !== 'undefined') {
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

    this._setupElevationCrosshair();

    // Bind print handlers so they can be removed on disconnect
    this._beforePrint = this.handleBeforePrint.bind(this);
    this._afterPrint  = this.handleAfterPrint.bind(this);
    window.addEventListener('beforeprint', this._beforePrint);
    window.addEventListener('afterprint',  this._afterPrint);
  }

  // A4 portrait printable area minus the print header (~25mm) leaves ~200mm
  // for the map. 200mm at 96dpi = 756px. Setting this on the container before
  // invalidateSize() tells Leaflet the true render target so it loads tiles to
  // fill the full area rather than leaving a grey void.
  handleBeforePrint() {
    const targetHeight = '756px';

    // Set height on both the wrapper and the Leaflet container itself
    this.containerTarget.style.height    = targetHeight;
    this.containerTarget.style.minHeight = targetHeight;

    const leafletContainer = this.containerTarget.querySelector('.leaflet-container');
    if (leafletContainer) {
      leafletContainer.style.height    = targetHeight;
      leafletContainer.style.minHeight = targetHeight;
    }

    const map = this.mapManager.map;
    map.invalidateSize({ animate: false });
    this.mapManager.fitAllBounds([0, 0]);

    map.once('moveend', () => {
      setTimeout(() => map.invalidateSize({ animate: false }), 150);
    });
  }

  handleAfterPrint() {
    this.containerTarget.style.height    = '60vh';
    this.containerTarget.style.minHeight = '500px';

    const leafletContainer = this.containerTarget.querySelector('.leaflet-container');
    if (leafletContainer) {
      leafletContainer.style.height    = '';
      leafletContainer.style.minHeight = '';
    }

    const map = this.mapManager.map;
    map.invalidateSize({ animate: false });
    this.mapManager.fitAllBounds([0, 0]);
  }

  displayWaypoints() {
    this.waypointsValue.forEach((waypoint, index) => {
      const lat      = waypoint.lat;
      const lon      = waypoint.lon;
      const type     = waypoint.type;
      const name     = waypoint.name || `Waypoint ${index + 1}`;
      const sequence = waypoint.sequence;
      const url      = waypoint.url;

      this.mapManager.addWaypointMarker(lat, lon, type, name, url);
    });
  }

  _setupElevationCrosshair() {
    const wrapper = document.getElementById('elevation-chart-wrapper');
    if (!wrapper) return;

    const elevationPoints = JSON.parse(wrapper.dataset.elevationPoints || '[]');
    if (!elevationPoints.length) return;

    const tryAttach = () => {
      const chartkickChart = Chartkick.charts['elevation-chart'];
      if (!chartkickChart) {
        this._chartRetries = (this._chartRetries || 0) + 1;
        if (this._chartRetries < 20) {
          this._chartRetryTimer = setTimeout(tryAttach, 100);
        }
        return;
      }

      const chart  = chartkickChart.getChartObject();
      const canvas = chart.canvas;

      this._onChartMousemove = (e) => {
        const elements = chart.getElementsAtEventForMode(e, 'index', { intersect: false }, false);
        if (!elements.length) return;

        const pt = elevationPoints[elements[0].index];
        if (!pt) return;

        if (this._elevationMarker) {
          this._elevationMarker.setLatLng([pt.lat, pt.lon]);
        } else {
          this._elevationMarker = L.circleMarker([pt.lat, pt.lon], {
            radius: 8,
            color: '#dc3545',
            fillColor: '#dc3545',
            fillOpacity: 0.8,
            weight: 2
          }).addTo(this.mapManager.map);
        }
      };

      this._onChartMouseleave = () => {
        if (this._elevationMarker) {
          this._elevationMarker.remove();
          this._elevationMarker = null;
        }
      };

      canvas.addEventListener('mousemove',  this._onChartMousemove);
      canvas.addEventListener('mouseleave', this._onChartMouseleave);
      this._elevationCanvas = canvas;
    };

    tryAttach();
  }

  disconnect() {
    if (this._chartRetryTimer) clearTimeout(this._chartRetryTimer);
    if (this._elevationCanvas) {
      this._elevationCanvas.removeEventListener('mousemove',  this._onChartMousemove);
      this._elevationCanvas.removeEventListener('mouseleave', this._onChartMouseleave);
    }
    if (this._elevationMarker) {
      this._elevationMarker.remove();
      this._elevationMarker = null;
    }
    window.removeEventListener('beforeprint', this._beforePrint);
    window.removeEventListener('afterprint',  this._afterPrint);
    if (this.mapManager) {
      this.mapManager.destroy();
    }
  }
}