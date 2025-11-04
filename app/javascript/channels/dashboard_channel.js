import consumer from "./consumer"

// Dashboard data fetcher - loads initial data
class DashboardDataFetcher {
  constructor() {
    this.isInitialized = false
  }

  async fetchDashboardData() {
    try {
      console.log("🌐 Fetching /dashboard.json...")
      const response = await fetch('/dashboard.json', {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (!response.ok) {
        console.error(`❌ HTTP error! status: ${response.status}`)
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      console.log("✅ Dashboard data received:", data)
      return data
    } catch (error) {
      console.error('❌ Error fetching dashboard data:', error)
      return null
    }
  }

  async initialize() {
    console.log("🔧 Initializing DashboardDataFetcher...")
    // Fetch initial data
    const data = await this.fetchDashboardData()
    if (data) {
      console.log("💾 Storing initial dashboard data globally")
      // Store data globally for map initialization
      window.initialDashboardData = data
      
      // Set last update time from the data's timestamp
      if (data.timestamp) {
        window.lastTelemetryUpdate = new Date(data.timestamp).getTime()
        console.log(`⏰ Set last update time to: ${data.timestamp}`)
      }
      
      console.log("🔄 Updating dashboard with initial data")
      this.updateDashboard(data)
      this.isInitialized = true
      
      // If map is already initialized, update it with data
      if (window.mapInitialized && window.updateMapWithData) {
        console.log("🗺️ Map already initialized, updating with data")
        window.updateMapWithData(data)
      } else {
        console.log("⏳ Map not initialized yet, data will be applied when map loads")
      }
    } else {
      console.error("❌ No data received from /dashboard.json")
    }
  }

  updateDashboard(data) {
    // Use the same update logic as ActionCable
    if (window.dashboardChannel) {
      window.dashboardChannel.updateDashboardWidgets(data)
      
      // Update trip polyline if trip points provided
      if (data.trip_points && data.trip_points.length > 0) {
        window.currentTripPoints = data.trip_points
        window.dashboardChannel.updateTripPolyline()
      }
    }
    
    // Update map if it's initialized
    if (window.mapInitialized && window.updateMapWithData) {
      window.updateMapWithData(data)
    }
  }
}

// Initialize global data fetcher
window.dashboardDataFetcher = new DashboardDataFetcher()

// Dashboard channel for real-time updates
const dashboardChannel = consumer.subscriptions.create("DashboardChannel", {
  connected() {
    console.log("✅ Connected to dashboard channel")
    // Reset connection status when connected
    this.updateConnectionStatus(true)
    // Start monitoring for stale data
    this.startConnectionMonitor()
  },

  disconnected() {
    console.log("❌ Disconnected from dashboard channel")
    this.updateConnectionStatus(false)
    this.stopConnectionMonitor()
  },

  received(data) {
    console.log("📡 Received data via ActionCable:", data)
    // Handle incoming real-time data
    this.updateDashboardWidgets(data)
    
    // Update last received timestamp
    window.lastTelemetryUpdate = Date.now()
    this.updateConnectionStatus(true)
    
    // For real-time updates, append to current trip points if travelling
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
    
    // Update heading indicator using pre-calculated direction from GPS
    if (data.gps && data.gps.direction) {
      this.updateHeadingIndicator(data.gps.direction, data.travelling, data.speed_kmh)
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
    
    // Plot today's trips on map
    if (data.todays_trips) {
      this.plotTodaysTrips(data.todays_trips)
    }
    
    // Update current trip polyline (clear and redraw with current points)
    if (data.trip_points) {
      this.updateCurrentTripPolyline(data.trip_points)
    }
  },

  updateTravellingStatus(travelling) {
    const statusElement = document.getElementById('travelling-status')
    if (!statusElement) return
    
    // Check if data is stale (no updates in last 5 minutes)
    const isStale = window.lastTelemetryUpdate && 
                    (Date.now() - window.lastTelemetryUpdate) > 5 * 60 * 1000
    
    if (isStale) {
      statusElement.innerHTML = '<div class="badge bg-warning text-dark w-100 py-2"><i class="bi bi-exclamation-triangle me-1"></i>Not Connected</div>'
    } else if (travelling) {
      statusElement.innerHTML = '<div class="badge bg-success w-100 py-2"><i class="bi bi-arrow-right-circle me-1"></i>Moving</div>'
    } else {
      statusElement.innerHTML = '<div class="badge bg-secondary w-100 py-2"><i class="bi bi-pause-circle me-1"></i>Stationary</div>'
    }
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
    
    // Check if data is stale (no updates in last 5 minutes)
    const isStale = window.lastTelemetryUpdate && 
                    (Date.now() - window.lastTelemetryUpdate) > 5 * 60 * 1000
    
    console.log(`🧭 Heading: ${direction}, Travelling: ${travelling}, Speed: ${speedRounded} km/h, Stale: ${isStale}`)
    
    // Show heading indicator unless Not Connected (stale data)
    if (!isStale && direction) {
      // Show/update heading indicator
      if (!headingIndicator) {
        // Create heading indicator
        console.log(`✨ Creating heading indicator: ${direction}`)
        headingIndicator = document.createElement('div')
        headingIndicator.id = 'heading-indicator'
        headingIndicator.innerHTML = `
          <div class="heading-direction">${direction}</div>
        `
        document.getElementById('dashboard-container').appendChild(headingIndicator)
      } else {
        // Update existing direction
        console.log(`🔄 Updating heading indicator: ${direction}`)
        const directionElement = headingIndicator.querySelector('.heading-direction')
        if (directionElement) directionElement.textContent = direction
      }
    } else {
      // Remove heading indicator when Not Connected (stale data)
      if (headingIndicator) {
        console.log(`🚫 Removing heading indicator (stale: ${isStale})`)
        headingIndicator.remove()
      }
    }
  },

  updateSpeedCircle(speedKmh, travelling) {
    let speedCircle = document.getElementById('speed-circle')
    const speedRounded = Math.round(speedKmh)
    
    // Check if data is stale (no updates in last 5 minutes)
    const isStale = window.lastTelemetryUpdate && 
                    (Date.now() - window.lastTelemetryUpdate) > 5 * 60 * 1000
    
    // Show speed circle unless Not Connected (stale data)
    if (!isStale) {
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
      // Remove speed circle when Not Connected (stale data)
      if (speedCircle) {
        speedCircle.remove()
      }
    }
  },

updateGPSInfo(gps) {
    if (!gps) {
      console.warn('⚠️ No GPS data provided to updateGPSInfo')
      return
    }
    
    console.log('📍 Updating GPS info:', gps)
    
    // Update latitude
    const latElement = document.getElementById('gps-latitude')
    if (latElement && gps.lat !== undefined && gps.lat !== null) {
      latElement.textContent = gps.lat.toFixed(6)
      console.log(`✅ Updated latitude: ${gps.lat.toFixed(6)}`)
    } else if (!latElement) {
      console.warn('⚠️ Latitude element (#gps-latitude) not found')
    }
    
    // Update longitude
    const lonElement = document.getElementById('gps-longitude')
    if (lonElement && gps.lon !== undefined && gps.lon !== null) {
      lonElement.textContent = gps.lon.toFixed(6)
      console.log(`✅ Updated longitude: ${gps.lon.toFixed(6)}`)
    } else if (!lonElement) {
      console.warn('⚠️ Longitude element (#gps-longitude) not found')
    }
    
    // Update altitude
    const altElement = document.getElementById('gps-altitude')
    if (altElement && gps.altitude !== undefined && gps.altitude !== null) {
      altElement.textContent = `${gps.altitude.toFixed(1)} m`
      console.log(`✅ Updated altitude: ${gps.altitude.toFixed(1)} m`)
    } else if (!altElement) {
      console.warn('⚠️ Altitude element (#gps-altitude) not found')
    }
    
    // Update satellites
    const satsElement = document.getElementById('gps-satellites')
    if (satsElement && gps.satellites !== undefined && gps.satellites !== null) {
      satsElement.textContent = gps.satellites
      console.log(`✅ Updated satellites: ${gps.satellites}`)
    } else if (!satsElement) {
      console.warn('⚠️ Satellites element (#gps-satellites) not found')
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
        Temp: ${temperature || '--'}Â°C<br>
        Speed: ${speedKmh || 0} km/h<br>
        Heading: ${Math.round(window.currentHeading || 0)}Â°
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
    
    // Update dewpoint
    const dewpointElement = document.querySelector('.widget-horizontal:has(.bi-moisture) .widget-value-small')
    if (dewpointElement) {
      const textNode = Array.from(dewpointElement.childNodes).find(node => node.nodeType === Node.TEXT_NODE)
      if (textNode) {
        textNode.textContent = weather.dewpoint || '--'
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
  },

  plotTodaysTrips(todays_trips) {
    if (!todays_trips || !todays_trips.trips) return
    if (!window.tripRoutesLayer) return
    
    console.log("🗺️ Plotting today's trips on map...")
    
    // Clear existing routes
    window.tripRoutesLayer.clearLayers()
    
    const trips = todays_trips.trips
    
    trips.forEach((trip) => {
      // Skip if no coordinates
      if (!trip.coordinates || trip.coordinates.length < 2) return
      
      // PostGIS geom coordinates are [lon, lat], but Leaflet needs [lat, lon]
      const latLngCoords = trip.coordinates.map(coord => [coord[1], coord[0]])
      
      // Create polyline for trip
      const polyline = L.polyline(latLngCoords, {
        color: '#3388ff',
        weight: 4,
        opacity: 0.7,
        smoothFactor: 1
      }).addTo(window.tripRoutesLayer)
      
      // Format times for popup
      const startTime = new Date(trip.start_time).toLocaleTimeString()
      const endTime = new Date(trip.end_time).toLocaleTimeString()
      
      // Add popup with trip info
      polyline.bindPopup(`
        <strong>${trip.name || 'Trip ' + trip.id}</strong><br>
        Time: ${startTime} - ${endTime}<br>
        Distance: ${trip.distance_km} km<br>
        Duration: ${trip.duration_minutes} min<br>
        Max Speed: ${trip.max_speed_kmh} km/h<br>
        Avg Speed: ${trip.avg_speed_kmh} km/h
      `)
    })
    
    console.log(`✅ Plotted ${trips.length} trip route(s) on map`)
  },

  updateCurrentTripPolyline(trip_points) {
    // Clear and redraw current trip polyline with provided points
    if (!window.dashboardMap) return
    
    // Remove old current trip polyline
    this.clearTripPolyline()
    
    // Draw new polyline if we have points
    if (trip_points && trip_points.length > 1) {
      console.log(`🔄 Redrawing current trip polyline with ${trip_points.length} points`)
      
      window.currentTripPoints = trip_points
      window.currentTripPolyline = L.polyline(trip_points, {
        color: '#3498db',  // Different color from saved trips
        weight: 4,
        opacity: 0.7
      }).addTo(window.dashboardMap)
    }
  },

  initGPSCollapse() {
    // Initialize GPS widget collapse functionality
    const header = document.querySelector('.gps-widget .widget-header.clickable')
    if (!header) return
    
    console.log('🎛️ Initializing GPS collapse functionality')
    
    header.addEventListener('click', () => {
      this.toggleGPSCollapse()
    })
    
    // Add keyboard support (Enter/Space)
    header.setAttribute('tabindex', '0')
    header.setAttribute('role', 'button')
    header.setAttribute('aria-expanded', 'false')
    header.setAttribute('aria-label', 'Toggle GPS information')
    
    header.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault()
        this.toggleGPSCollapse()
      }
    })
  },

  toggleGPSCollapse() {
    const details = document.querySelector('.gps-widget .gps-details')
    const icon = document.querySelector('.gps-widget .collapse-icon')
    const header = document.querySelector('.gps-widget .widget-header.clickable')
    
    if (!details || !icon) return
    
    const isCollapsed = details.classList.contains('collapsed')
    
    if (isCollapsed) {
      // Expand
      details.classList.remove('collapsed')
      details.classList.add('expanded')
      icon.classList.add('expanded')
      if (header) header.setAttribute('aria-expanded', 'true')
      console.log('📍 GPS info expanded')
    } else {
      // Collapse
      details.classList.remove('expanded')
      details.classList.add('collapsed')
      icon.classList.remove('expanded')
      if (header) header.setAttribute('aria-expanded', 'false')
      console.log('📍 GPS info collapsed')
    }
  },

  startConnectionMonitor() {
    // Check connection status every 10 seconds
    this.connectionMonitorInterval = setInterval(() => {
      this.updateConnectionStatus(true)
    }, 10000)
  },

  stopConnectionMonitor() {
    if (this.connectionMonitorInterval) {
      clearInterval(this.connectionMonitorInterval)
      this.connectionMonitorInterval = null
    }
  },

  updateConnectionStatus(checkStale) {
    if (!checkStale) {
      // Disconnected
      this.updateTravellingStatus(false)
      return
    }
    
    // Check if we have recent data
    const isStale = window.lastTelemetryUpdate && 
                    (Date.now() - window.lastTelemetryUpdate) > 5 * 60 * 1000
    
    if (isStale) {
      // Trigger update to show "Not Connected"
      this.updateTravellingStatus(false)
    }
  }
})

// Store reference globally for fetcher to use
window.dashboardChannel = dashboardChannel
console.log("📺 Dashboard channel created and stored globally")

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  console.log("🚀 DOMContentLoaded - Starting dashboard initialization")
  
  // Initialize GPS collapse functionality
  if (window.dashboardChannel) {
    window.dashboardChannel.initGPSCollapse()
  }
  
  // Wait a brief moment for ActionCable to fully initialize
  setTimeout(() => {
    // Initialize the data fetcher (loads initial data only)
    console.log("📥 Fetching initial dashboard data...")
    window.dashboardDataFetcher.initialize().then(() => {
      console.log("✅ Dashboard initialized with async data loading")
    }).catch(error => {
      console.error("❌ Failed to initialize dashboard:", error)
    })
  }, 100)
})

// Also initialize on Turbo load
document.addEventListener('turbo:load', () => {
  console.log("🔄 Turbo load event")
  if (!window.dashboardDataFetcher.isInitialized) {
    console.log("📥 Fetching initial dashboard data (turbo)...")
    window.dashboardDataFetcher.initialize().then(() => {
      console.log("✅ Dashboard initialized with async data loading (turbo)")
    }).catch(error => {
      console.error("❌ Failed to initialize dashboard (turbo):", error)
    })
  } else {
    console.log("ℹ️ Dashboard already initialized, skipping")
  }
})