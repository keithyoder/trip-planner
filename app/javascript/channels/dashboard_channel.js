import consumer from "./consumer"

consumer.subscriptions.create("DashboardChannel", {
  connected() {
    console.log("Connected to dashboard channel")
  },

  disconnected() {
    console.log("Disconnected from dashboard channel")
  },

  received(data) {
    // Handle incoming data
    this.updateDashboardWidgets(data)
  },

  updateDashboardWidgets(data) {
    console.log("Updating dashboard with data:", data)
    
    // Guard clause - return if data is null or undefined
    if (!data) {
      console.error("Dashboard data is null or undefined")
      return
    }
    
    // Update travelling status
    this.updateTravellingStatus(data.travelling)
    
    // Update odometer
    this.updateOdometer(data.distance_km || 0)
    
    // Update speed widget (show/hide based on travelling status)
    this.updateSpeedWidget(data.speed_kmh, data.travelling)
    
    // Update GPS info
    if (data.gps) {
      this.updateGPSInfo(data.gps)
    }
    
    // Update map marker position
    if (data.gps) {
      this.updateMapMarker(data.gps, data.temperature, data.speed_kmh)
    }
    
    // Update weather sidebar
    if (data.weather) {
      this.updateWeatherSidebar(data.weather)
    }
  },

  updateTravellingStatus(travelling) {
    const statusElement = document.getElementById('travelling-status')
    if (!statusElement) return
    
    statusElement.innerHTML = travelling
      ? '<div class="badge bg-success w-100 py-2"><i class="bi bi-arrow-right-circle me-1"></i>Moving</div>'
      : '<div class="badge bg-secondary w-100 py-2"><i class="bi bi-pause-circle me-1"></i>Stationary</div>'
  },

  updateOdometer(distanceKm) {
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
  },

  updateSpeedWidget(speedKmh, travelling) {
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
  },

  updateGPSInfo(gps) {
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
  },

  updateMapMarker(gps, temperature, speedKmh) {
    if (!window.currentMarker || !gps || !gps.lat || !gps.lon) return
    
    try {
      const oldPos = window.currentMarker.getLatLng();
      const newPos = [gps.lat, gps.lon];
      
      // Calculate heading/bearing if position changed
      if (oldPos.lat !== newPos[0] || oldPos.lng !== newPos[1]) {
                // Update marker position
        window.currentMarker.setLatLng(newPos);
        
        // Rotate the car icon
        this.rotateCarIcon(gps.heading);
        
        // Optionally pan map to new location when moving
        if (speedKmh > 1) {
          window.dashboardMap.panTo(newPos, {animate: true, duration: 0.5});
        }
      }
      
      // Update popup content
      window.currentMarker.bindPopup(`
        <strong>Current Location</strong><br>
        Temp: ${temperature || '--'}°C<br>
        Speed: ${speedKmh || 0} km/h<br>
        Heading: ${Math.round(window.currentHeading || 0)}°
      `);
    } catch (error) {
      console.error("Error updating map marker:", error)
    }
  },

  updateWeatherSidebar(weather) {
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
})