import consumer from "./consumer"

// Dashboard Data Fetcher class
class DashboardDataFetcher {
  constructor() {
    this.isInitialized = false
  }

  async initialize() {
    if (this.isInitialized) {
      console.log("ℹ️ Dashboard already initialized")
      return
    }

    try {
      const data = await this.fetchDashboardData()
      if (data) {
        this.updateDashboard(data)
        this.isInitialized = true
      }
    } catch (error) {
      console.error("❌ Failed to fetch initial dashboard data:", error)
    }
  }

  async fetchDashboardData() {
    try {
      const response = await fetch('/dashboard.json')
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      const data = await response.json()
      console.log("📦 Fetched dashboard data:", data)
      return data
    } catch (error) {
      console.error("❌ Error fetching dashboard data:", error)
      return null
    }
  }

  updateDashboard(data) {
    // Store data globally for map initialization
    window.initialDashboardData = data
    
    // If map already initialized, update it
    if (window.mapInitialized && window.updateMapWithData) {
      window.updateMapWithData(data)
    }
  }
}

// Only initialize dashboard channel if we're on the dashboard page
function isDashboardPage() {
  return document.getElementById('dashboard-container') !== null
}

// Initialize dashboard only on dashboard pages
function initializeDashboard() {
  if (!isDashboardPage()) {
    console.log("ℹ️ Not on dashboard page, skipping dashboard initialization")
    return
  }

  console.log("🚀 Initializing dashboard...")

  // Initialize global data fetcher if not already created
  if (!window.dashboardDataFetcher) {
    window.dashboardDataFetcher = new DashboardDataFetcher()
  }

  // Create dashboard channel subscription if not already created
  if (!window.dashboardChannel) {
    window.dashboardChannel = consumer.subscriptions.create("DashboardChannel", {
      connected() {
        console.log("✅ Connected to dashboard channel")
        this.updateConnectionStatus(true)
        this.startConnectionMonitor()
      },

      disconnected() {
        console.log("❌ Disconnected from dashboard channel")
        this.updateConnectionStatus(false)
        this.stopConnectionMonitor()
      },

      received(data) {
        console.log("📡 Received data via ActionCable:", data)
        this.updateDashboardWidgets(data)
        
        window.lastTelemetryUpdate = Date.now()
        this.updateConnectionStatus(true)
        
        if (data.gps && data.travelling) {
          window.currentTripPoints.push([data.gps.lat, data.gps.lon])
          this.updateTripPolyline()
        }
      },

      updateDashboardWidgets(data) {
        console.log("Updating dashboard with data:", data)
        
        if (!data) {
          console.error("Dashboard data is null or undefined")
          return
        }
        
        this.updateTravellingStatus(data.travelling)
        this.updateOdometer(data.distance_km || 0)
        
        if (data.gps && data.gps.direction) {
          this.updateHeadingIndicator(data.gps.direction, data.travelling, data.speed_kmh)
        }
        
        if (data.gps) {
          this.updateGPSWidget(data.gps)
        }
        
        if (data.weather) {
          this.updateWeatherWidget(data.weather)
        }
        
        if (window.dashboardMap && data.gps) {
          this.updateMapLocation(data.gps)
        }
      },

      updateTravellingStatus(isTravelling) {
        const statusElement = document.getElementById('travelling-status')
        const statusIcon = document.getElementById('status-icon')
        const statusText = document.getElementById('status-text')
        
        if (statusElement && statusIcon && statusText) {
          if (isTravelling) {
            statusElement.classList.remove('not-connected')
            statusElement.classList.add('travelling')
            statusIcon.textContent = '🚗'
            statusText.textContent = 'Travelling'
          } else {
            const isStale = window.lastTelemetryUpdate && 
                           (Date.now() - window.lastTelemetryUpdate) > 5 * 60 * 1000
            
            if (isStale || !window.lastTelemetryUpdate) {
              statusElement.classList.remove('travelling')
              statusElement.classList.add('not-connected')
              statusIcon.textContent = '📡'
              statusText.textContent = 'Not Connected'
            } else {
              statusElement.classList.remove('travelling', 'not-connected')
              statusIcon.textContent = '🅿️'
              statusText.textContent = 'Parked'
            }
          }
        }
      },

      updateOdometer(distanceKm) {
        const odometerValue = document.getElementById('odometer-value')
        if (odometerValue) {
          odometerValue.textContent = distanceKm.toFixed(1)
        }
      },

      updateHeadingIndicator(direction, isTravelling, speedKmh) {
        const headingContainer = document.getElementById('heading-indicator-container')
        if (!headingContainer) return
        
        if (isTravelling) {
          headingContainer.classList.add('visible')
          const arrow = document.getElementById('heading-arrow')
          const text = document.getElementById('heading-text')
          const speed = document.getElementById('heading-speed')
          
          if (arrow && direction.degrees !== undefined) {
            arrow.style.transform = `rotate(${direction.degrees}deg)`
          }
          
          if (text && direction.cardinal) {
            text.textContent = direction.cardinal
          }
          
          if (speed && speedKmh !== undefined) {
            speed.textContent = `${Math.round(speedKmh)} km/h`
          }
        } else {
          headingContainer.classList.remove('visible')
        }
      },

      updateGPSWidget(gps) {
        const elements = {
          lat: document.getElementById('gps-latitude'),
          lon: document.getElementById('gps-longitude'),
          alt: document.getElementById('gps-altitude'),
          accuracy: document.getElementById('gps-accuracy'),
          satellites: document.getElementById('gps-satellites')
        }
        
        if (elements.lat) elements.lat.textContent = gps.lat.toFixed(6)
        if (elements.lon) elements.lon.textContent = gps.lon.toFixed(6)
        if (elements.alt) elements.alt.textContent = `${Math.round(gps.altitude || 0)} m`
        if (elements.accuracy) elements.accuracy.textContent = `${(gps.accuracy || 0).toFixed(1)} m`
        if (elements.satellites) elements.satellites.textContent = gps.satellites || 0
      },

      updateWeatherWidget(weather) {
        const elements = {
          temp: document.getElementById('weather-temperature'),
          humidity: document.getElementById('weather-humidity'),
          dewpoint: document.getElementById('weather-dewpoint'),
          pressure: document.getElementById('weather-pressure')
        }
        
        if (elements.temp && weather.temperature !== undefined) {
          elements.temp.textContent = `${weather.temperature.toFixed(1)}°C`
        }
        if (elements.humidity && weather.humidity !== undefined) {
          elements.humidity.textContent = `${weather.humidity}%`
        }
        if (elements.dewpoint && weather.dew_point !== undefined) {
          elements.dewpoint.textContent = `${weather.dew_point.toFixed(1)}°C`
        }
        if (elements.pressure && weather.pressure !== undefined) {
          elements.pressure.textContent = `${weather.pressure.toFixed(1)} hPa`
        }
      },

      updateMapLocation(gps) {
        if (!window.dashboardMap) return
        
        if (!window.currentMarker) {
          const carIcon = L.divIcon({
            html: '<div class="car-icon-container"><img src="/assets/car-icon.svg" alt="car" /></div>',
            className: 'car-marker',
            iconSize: [32, 32],
            iconAnchor: [16, 16]
          })
          
          window.currentMarker = L.marker([gps.lat, gps.lon], { icon: carIcon })
            .addTo(window.dashboardMap)
        } else {
          window.currentMarker.setLatLng([gps.lat, gps.lon])
        }
        
        window.dashboardMap.setView([gps.lat, gps.lon], window.dashboardMap.getZoom())
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
        if (!window.dashboardMap || !window.currentTripPoints || window.currentTripPoints.length < 2) return
        
        if (window.currentTripPolyline) {
          window.currentTripPolyline.setLatLngs(window.currentTripPoints)
        } else {
          window.currentTripPolyline = L.polyline(window.currentTripPoints, {
            color: '#0066ff',
            weight: 4,
            opacity: 0.7
          }).addTo(window.dashboardMap)
        }
      },

      initGPSCollapse() {
        const trigger = document.getElementById('gps-collapse-trigger')
        const content = document.getElementById('gps-details-content')
        const icon = document.getElementById('gps-collapse-icon')
        const header = document.getElementById('gps-widget-header')
        
        if (!trigger || !content) return
        
        trigger.addEventListener('click', () => {
          const isExpanded = content.classList.contains('show')
          
          if (isExpanded) {
            content.classList.remove('show')
            if (icon) icon.classList.remove('expanded')
            if (header) header.setAttribute('aria-expanded', 'false')
            console.log('📍 GPS info collapsed')
          } else {
            content.classList.add('show')
            if (icon) icon.classList.add('expanded')
            if (header) header.setAttribute('aria-expanded', 'true')
            console.log('📍 GPS info expanded')
          }
        })
      },

      startConnectionMonitor() {
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
          this.updateTravellingStatus(false)
          return
        }
        
        const isStale = window.lastTelemetryUpdate && 
                        (Date.now() - window.lastTelemetryUpdate) > 5 * 60 * 1000
        
        if (isStale) {
          this.updateTravellingStatus(false)
        }
      }
    })
    
    console.log("📺 Dashboard channel created")
  }

  // Initialize GPS collapse functionality
  if (window.dashboardChannel) {
    window.dashboardChannel.initGPSCollapse()
  }
  
  // Fetch initial data after a brief delay
  setTimeout(() => {
    console.log("📥 Fetching initial dashboard data...")
    window.dashboardDataFetcher.initialize().then(() => {
      console.log("✅ Dashboard initialized with async data loading")
    }).catch(error => {
      console.error("❌ Failed to initialize dashboard:", error)
    })
  }, 100)
}

// Initialize on DOMContentLoaded
document.addEventListener('DOMContentLoaded', () => {
  initializeDashboard()
})

// Initialize on Turbo load
document.addEventListener('turbo:load', () => {
  initializeDashboard()
})