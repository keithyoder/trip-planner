import { StreamActions } from "@hotwired/turbo"

// Register custom Turbo Stream action
StreamActions.update_dashboard = function() {
  // Find the script tag with our data
  const scriptTag = this.templateContent.querySelector('script[data-dashboard-update]')
  
  console.log("Looking for dashboard data...")
  console.log("Template content:", this.templateContent)
  console.log("Script tag found:", scriptTag)
  
  if (!scriptTag) {
    console.error("No script tag with dashboard data found")
    return
  }
  
  try {
    const data = JSON.parse(scriptTag.textContent)
    console.log("Parsed dashboard data:", data)
    updateDashboardWidgets(data)
  } catch (e) {
    console.error("Failed to parse dashboard data:", e)
    console.error("Script content was:", scriptTag.textContent)
  }
}

function updateDashboardWidgets(data) {
  console.log("Updating dashboard with data:", data)
  
  // Guard clause - return if data is null or undefined
  if (!data) {
    console.error("Dashboard data is null or undefined")
    return
  }
  
  // Update travelling status
  updateTravellingStatus(data.travelling)
  
  // Update odometer
  updateOdometer(data.distance_km || 0)
  
  // Update speed widget (show/hide based on travelling status)
  updateSpeedWidget(data.speed_kmh, data.travelling)
  
  // Update GPS info
  if (data.gps) {
    updateGPSInfo(data.gps)
  }
  
  // Update map marker position
  if (data.gps) {
    updateMapMarker(data.gps, data.temperature, data.speed_kmh)
  }
  
  // Update weather sidebar
  if (data.weather) {
    updateWeatherSidebar(data.weather)
  }
}

function updateTravellingStatus(travelling) {
  const statusElement = document.getElementById('travelling-status')
  if (!statusElement) return
  
  statusElement.innerHTML = travelling 
    ? '<div class="badge bg-success w-100 py-2"><i class="bi bi-arrow-right-circle me-1"></i>Moving</div>'
    : '<div class="badge bg-secondary w-100 py-2"><i class="bi bi-pause-circle me-1"></i>Stationary</div>'
}

function updateOdometer(distanceKm) {
  const container = document.querySelector('.odometer-container')
  if (!container) return
  
  const digits = distanceKm.toFixed(1).padStart(7, '0').split('')
  
  container.innerHTML = digits.map(digit => {
    if (digit === '.') {
      return '<div class="odometer-separator">.</div>'
    } else {
      return `<div class="odometer-digit">${digit}</div>`
    }
  }).join('')
}

function updateSpeedWidget(speedKmh, travelling) {
  const container = document.getElementById('dashboard-widgets-left')
  if (!container) return
  
  // Find existing speed widget
  let speedWidget = container.querySelector('.widget.speed-widget')
  
  if (travelling && speedKmh > 0) {
    // Show/update speed widget
    if (!speedWidget) {
      // Create speed widget
      speedWidget = document.createElement('div')
      speedWidget.className = 'widget speed-widget'
      speedWidget.innerHTML = `
        <div class="widget-icon">
          <i class="bi bi-speedometer2 text-success"></i>
        </div>
        <div class="widget-value">
          <span class="speed-value">${speedKmh}</span>
          <span class="widget-unit">km/h</span>
        </div>
        <div class="widget-label">Speed</div>
      `
      // Insert after odometer widget
      const odometer = container.querySelector('.odometer-widget')
      if (odometer && odometer.nextSibling) {
        container.insertBefore(speedWidget, odometer.nextSibling)
      } else if (odometer) {
        container.appendChild(speedWidget)
      }
    } else {
      // Update existing speed value
      const speedValue = speedWidget.querySelector('.speed-value')
      if (speedValue) speedValue.textContent = speedKmh
    }
  } else {
    // Remove speed widget when not travelling
    if (speedWidget) {
      speedWidget.remove()
    }
  }
}

function updateGPSInfo(gps) {
  if (!gps) return
  
  // Update latitude
  const latElement = document.querySelector('.gps-details .gps-row:nth-child(1) .gps-value')
  if (latElement && gps.lat) {
    latElement.textContent = gps.lat.toFixed(6)
  }
  
  // Update longitude
  const lonElement = document.querySelector('.gps-details .gps-row:nth-child(2) .gps-value')
  if (lonElement && gps.lon) {
    lonElement.textContent = gps.lon.toFixed(6)
  }
  
  // Update altitude if element exists
  const altElement = document.querySelector('.gps-details .gps-row:nth-child(3) .gps-value')
  if (altElement && gps.altitude) {
    altElement.textContent = `${gps.altitude.toFixed(1)} m`
  }
  
  // Update satellites if element exists
  const satsElement = document.querySelector('.gps-details .gps-row:nth-child(4) .gps-value')
  if (satsElement && gps.satellites) {
    satsElement.textContent = gps.satellites
  }
}

function updateMapMarker(gps, temperature, speedKmh) {
  if (!window.currentMarker || !gps || !gps.lat || !gps.lon) return
  
  try {
    // Update marker position
    window.currentMarker.setLatLng([gps.lat, gps.lon])
    
    // Rebind popup with updated content
    window.currentMarker.bindPopup(`
      <strong>Current Location</strong><br>
      Temp: ${temperature || '--'}°C<br>
      Speed: ${speedKmh || 0} km/h
    `)
    
    // Optionally pan map to new location (uncomment if desired)
    // window.dashboardMap.panTo([gps.lat, gps.lon])
  } catch (error) {
    console.error("Error updating map marker:", error)
  }
}

function updateWeatherSidebar(weather) {
  if (!weather) return
  
  // Update temperature
  const tempElement = document.querySelector('.widget-horizontal:has(.bi-thermometer-half) .widget-value-small')
  if (tempElement) {
    const textNode = Array.from(tempElement.childNodes).find(node => node.nodeType === Node.TEXT_NODE)
    if (textNode) {
      textNode.textContent = weather.temperature || '--'
    }
  }
  
  // Update humidity
  const humidityElement = document.querySelector('.widget-horizontal:has(.bi-droplet) .widget-value-small')
  if (humidityElement) {
    const textNode = Array.from(humidityElement.childNodes).find(node => node.nodeType === Node.TEXT_NODE)
    if (textNode) {
      textNode.textContent = weather.humidity || '--'
    }
  }
  
  // Update pressure
  const pressureElement = document.querySelector('.widget-horizontal:has(.bi-speedometer) .widget-value-small')
  if (pressureElement) {
    const textNode = Array.from(pressureElement.childNodes).find(node => node.nodeType === Node.TEXT_NODE)
    if (textNode) {
      textNode.textContent = weather.pressure || '--'
    }
  }
}

// Export for testing/debugging
window.updateDashboardWidgets = updateDashboardWidgets