import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import "leaflet-css"
import $ from 'jquery'
import wkt from 'wicket'

// Connects to data-controller="routes"
export default class extends Controller {
  static targets = ["container"]

    connect() {
    var map = L.map(this.containerTarget).setView(
      [$('#routescontainer').data('lon'), $('#routescontainer').data('lat')],
      14
    );
    var vectorLayer = L.geoJSON([], {
        style: {
            weight: 2,
            color: 'blue',
        },
        pointToLayer: function(feature, latlng) {
            return L.circleMarker(latlng, geojsonMarkerOptions);
        }
    });
    vectorLayer.addTo(map);
    var wicket = new wkt.Wkt();
    wicket.read($('#routescontainer').data('route'));
    vectorLayer.addData(wicket.toJson());
    map.fitBounds(vectorLayer.getBounds());
    map.setZoom(Math.min(map.getZoom(), 18), {animate: false});

    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(map);
  }

  disconnect() {
    this.map.remove();
  }
}