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
    if (data.gps && data.travelling) {
      window.currentTripPoints.push([data.gps.lat, data.gps.lon])
      this.updateTripPolyline()
    }
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
    
    // Update heading indicator using pre-calculated direction
    if (data.direction) {
      this.updateHeadingIndicator(data.direction, data.travelling, data.speed_kmh)
    }
    
    // Update speed circle (show/hide based on travelling status)
    this.updateSpeedCircle(data.speed_kmh, data.travelling)
    
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

  updateHeadingIndicator(direction, travelling, speedKmh) {
    let headingIndicator = document.getElementById('heading-indicator')
    const speedRounded = Math.round(speedKmh)
    
    if (travelling && speedRounded > 1 && direction) {
      // Show/update heading indicator
      if (!headingIndicator) {
        // Create heading indicator
        headingIndicator = document.createElement('div')
        headingIndicator.id = 'heading-indicator'
        headingIndicator.innerHTML = `
          <div class="heading-direction">${direction}</div>
        `
        document.getElementById('dashboard-container').appendChild(headingIndicator)
      } else {
        // Update existing direction
        const directionElement = headingIndicator.querySelector('.heading-direction')
        if (directionElement) directionElement.textContent = direction
      }
    } else {
      // Remove heading indicator when not travelling or speed too low
      if (headingIndicator) {
        headingIndicator.remove()
      }
    }
  },

  updateSpeedCircle(speedKmh, travelling) {
    let speedCircle = document.getElementById('speed-circle')
    const speedRounded = Math.round(speedKmh)
    
    if (travelling && speedRounded > 1) {
      // Show/update speed circle
      if (!speedCircle) {
        // Create speed circle
        speedCircle = document.createElement('div')
        speedCircle.id = 'speed-circle'
        speedCircle.innerHTML = `
          <div class="speed-circle-value">${speedRounded}</div>
          <div class="speed-circle-unit">km/h</div>
        `
        document.getElementById('dashboard-container').appendChild(speedCircle)
      } else {
        // Update existing speed value
        const speedValue = speedCircle.querySelector('.speed-circle-value')
        if (speedValue) speedValue.textContent = speedRounded
      }
    } else {
      // Remove speed circle when not travelling or speed too low
      if (speedCircle) {
        speedCircle.remove()
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
      const oldPos = window.currentMarker.getLatLng()
      const newPos = [gps.lat, gps.lon]
      
      // Calculate heading/bearing if position changed
      if (oldPos.lat !== newPos[0] || oldPos.lng !== newPos[1]) {
        // Update marker position
        window.currentMarker.setLatLng(newPos)
        
        // Rotate the car icon
        this.rotateCarIcon(gps.heading)
        
        // Optionally pan map to new location when moving
        if (speedKmh > 1) {
          window.dashboardMap.panTo(newPos, {animate: true, duration: 0.5})
        }
      }
      
      // Update popup content
      window.currentMarker.bindPopup(`
        <strong>Current Location</strong><br>
        Temp: ${temperature || '--'}°C<br>
        Speed: ${speedKmh || 0} km/h<br>
        Heading: ${Math.round(window.currentHeading || 0)}°
      `)
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
  },

  rotateCarIcon(heading) {
    if (!window.currentMarker) return
    
    // Store current heading
    window.currentHeading = heading
    
    // Get the marker icon element
    const icon = window.currentMarker._icon
    if (!icon) return
    
    // Find the car icon container
    const carContainer = icon.querySelector('.car-icon-container')
    if (!carContainer) return
    
    // Apply rotation
    carContainer.style.transform = `rotate(${heading}deg)`
    carContainer.style.transition = 'transform 0.3s ease'
  },

  updateTripPolyline() {
    // Remove old polyline if exists
    if (window.currentTripPolyline) {
      window.dashboardMap.removeLayer(window.currentTripPolyline)
    }
    
    // Draw new polyline with all points
    if (window.currentTripPoints.length > 1) {
      window.currentTripPolyline = L.polyline(window.currentTripPoints, {
        color: '#3498db',
        weight: 4,
        opacity: 0.7
      }).addTo(window.dashboardMap)
    }
  },

  clearTripPolyline() {
    if (window.currentTripPolyline) {
      window.dashboardMap.removeLayer(window.currentTripPolyline)
      window.currentTripPolyline = null
    }
  }
})