import consumer from "./consumer"

const DISTANCE_UNIT = document.querySelector('meta[name="distance-unit"]')?.content || 'km'

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
    
    // Update all dashboard widgets with initial data
    if (window.dashboardChannel) {
      window.dashboardChannel.updateDashboardWidgets(data)
    }
    
    // If map already initialized, update it
    if (window.mapInitialized && window.updateMapWithData) {
      window.updateMapWithData(data)
    } else {
      // Initialize map if not yet done
      if (window.dashboardChannel) {
        window.dashboardChannel.initializeMap()
      }
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
        this.startConnectionMonitor()
        
        // Initialize trip tracking
        if (!window.currentTripPoints) {
          window.currentTripPoints = []
        }
        
        // Initialize GPS collapse after a short delay to ensure DOM is ready
        setTimeout(() => {
          this.initGPSCollapse()
        }, 200)
      },

      disconnected() {
        console.log("❌ Disconnected from dashboard channel")
        this.stopConnectionMonitor()
      },

      received(data) {
        window.lastTelemetryUpdate = Date.now()
        const justStartedTravelling = data.travelling && !window.wasTravelling

        this.updateDashboardWidgets(data)

        if (data.gps && data.travelling) {
          if (justStartedTravelling && window.dashboardDataFetcher) {
            // Trip just got confirmed — backfill the points we missed during the debounce window
            console.log('🚗 Trip confirmed, backfilling full trip history')
            window.dashboardDataFetcher.fetchDashboardData().then(freshData => {
              if (freshData) {
                window.currentTripPoints = freshData.trip_points || []
                this.updateTripPolyline()
              }
            })
          } else {
            window.currentTripPoints.push([data.gps.lat, data.gps.lon])
            this.updateTripPolyline()
          }
        }

        window.wasTravelling = !!data.travelling
      },

      updateDashboardWidgets(data) {
        console.log("🔄 Updating dashboard with data:", data)
        
        if (!data) {
          console.error("❌ Dashboard data is null or undefined")
          return
        }
        
        // Update last telemetry timestamp
        window.lastTelemetryUpdate = new Date(data.timestamp).getTime()
        
        this.updateTravellingStatus(data.travelling, data.transport_mode)
        this.updateOdometer(data.distance_km || 0)
        
        if (data.gps && data.gps.direction) {
          this.updateHeadingIndicator(data.gps.direction, data.travelling, data.speed_kmh)
          // Rotate car icon when travelling and heading is available
          if (data.travelling && data.gps.heading !== undefined) {
            this.rotateCarIcon(data.gps.heading)
          }
        }
    
        // Update speed circle (show/hide based on travelling status)
        this.updateSpeedCircle(data.speed_kmh, data.travelling)
        
        if (data.gps) {
          this.updateGPSWidget(data.gps)
        }
        
        if (data.weather) {
          this.updateWeatherWidget(data.weather)
        }
        
        if (window.dashboardMap && data.gps) {
          this.updateMapLocation(data.gps)
        }
        
        // Only resync when the server explicitly included trip_points (i.e. this came
        // from a /dashboard.json fetch, not a live ActionCable broadcast — those never
        // include this key and shouldn't wipe what we're incrementally building).
        if (data.trip_points !== undefined) {
          window.currentTripPoints = data.trip_points
          console.log(`📍 Syncing ${window.currentTripPoints.length} trip point(s)`)
          this.updateTripPolyline()
        }
        
        // Plot today's completed trips
        if (data.todays_trips && data.todays_trips.trips) {
          this.plotTodaysTrips(data.todays_trips.trips)
        }
      },

      updateTravellingStatus(isTravelling, transportMode) {
        const statusElement = document.getElementById('travelling-status')
        if (!statusElement) {
          console.warn("⚠️ travelling-status element not found")
          return
        }

        const badge = statusElement.querySelector('.badge')
        if (!badge) {
          console.warn("⚠️ badge element not found inside travelling-status")
          return
        }

        badge.classList.remove('bg-success', 'bg-secondary', 'bg-warning', 'text-dark', 'text-white')

        const isStale = window.lastTelemetryUpdate &&
                      (Date.now() - window.lastTelemetryUpdate) > 5 * 60 * 1000

        const MODE_LABELS = { automotive: 'Driving', driving: 'Driving', walking: 'Walking', running: 'Running', cycling: 'Cycling' }
        const MODE_ICONS  = { automotive: 'bi-car-front', driving: 'bi-car-front', walking: 'bi-person-walking', running: 'bi-person-running', cycling: 'bi-bicycle' }

        if (isTravelling) {
          badge.classList.add('bg-success', 'text-white')
          const mode = transportMode || 'driving'
          const label = MODE_LABELS[mode] || (mode.charAt(0).toUpperCase() + mode.slice(1))
          const icon = MODE_ICONS[mode] || 'bi-car-front'
          badge.innerHTML = `<i class="bi ${icon} me-1"></i>${label}`
          console.log(`✅ Status: ${label}`)
        } else if (isStale || !window.lastTelemetryUpdate) {
          badge.classList.add('bg-warning', 'text-dark')
          badge.innerHTML = '<i class="bi bi-exclamation-triangle me-1"></i>Not Connected'
          console.log("⚠️ Status: Not Connected")
        } else {
          badge.classList.add('bg-secondary', 'text-white')
          badge.innerHTML = '<i class="bi bi-p-circle me-1"></i>Stationary'
          console.log("🅿️ Status: Stationary")
        }
      },

      updateOdometer(distanceKm) {
        const value = DISTANCE_UNIT === 'miles' ? distanceKm * 0.621371 : distanceKm
        const container = document.querySelector('.odometer-container')
        if (!container) return
        
        const digits = value.toFixed(1).padStart(7, '0').split('')
        
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

      updateGPSWidget(gps) {
        const elements = {
          lat: document.getElementById('gps-latitude'),
          lon: document.getElementById('gps-longitude'),
          alt: document.getElementById('gps-altitude'),
          satellites: document.getElementById('gps-satellites')
        }
        
        if (elements.lat) elements.lat.textContent = gps.lat.toFixed(6)
        if (elements.lon) elements.lon.textContent = gps.lon.toFixed(6)
        if (elements.alt) elements.alt.textContent = `${Math.round(gps.altitude || 0)} m`
        if (elements.satellites) elements.satellites.textContent = gps.satellites || 0
      },

      updateWeatherWidget(weather) {
        const elements = {
          temp: document.getElementById('weather-temperature'),
          humidity: document.getElementById('weather-humidity'),
          dewpoint: document.getElementById('weather-dewpoint'),
          pressure: document.getElementById('weather-pressure')
        }
        
        if (elements.temp && weather.temperature !== undefined && weather.temperature !== null) {
          elements.temp.innerHTML = `${weather.temperature.toFixed(1)}<span class="widget-unit-small">°C</span>`
        }
        if (elements.humidity && weather.humidity !== undefined && weather.humidity !== null) {
          elements.humidity.innerHTML = `${weather.humidity}<span class="widget-unit-small">%</span>`
        }
        if (elements.dewpoint && weather.dewpoint !== undefined && weather.dewpoint !== null) {
          elements.dewpoint.innerHTML = `${weather.dewpoint.toFixed(1)}<span class="widget-unit-small">°C</span>`
        }
        if (elements.pressure && weather.pressure !== undefined && weather.pressure !== null) {
          elements.pressure.innerHTML = `${weather.pressure.toFixed(1)}<span class="widget-unit-small">hPa</span>`
        }
      },

      initializeMap() {
        const mapElement = document.getElementById('map')
        if (!mapElement || window.mapInitialized) {
          console.log("ℹ️ Map already initialized or element not found")
          return
        }

        console.log("🗺️ Initializing dashboard map...")

        // Use initial data if available
        const data = window.initialDashboardData
        const lat = data?.gps?.lat || -23.5505
        const lon = data?.gps?.lon || -46.6333
        const zoom = data?.gps ? 16 : 2

        // Create map - use 'map' ID not 'dashboard-map'
        window.dashboardMap = L.map('map', {
          zoomControl: false
        }).setView([lat, lon], zoom)
        
        // Add zoom control to bottom right
        L.control.zoom({
          position: 'bottomright'
        }).addTo(window.dashboardMap)

        // Add tile layer
        L.tileLayer('https://tiles.stadiamaps.com/tiles/outdoors/{z}/{x}/{y}.png?api_key=50e54c7f-f220-44f9-875c-a0ce16bc63b5', {
          attribution: '© OpenStreetMap contributors',
          maxZoom: 19
        }).addTo(window.dashboardMap)

        // Initialize trip points array
        if (!window.currentTripPoints) {
          window.currentTripPoints = []
        }

        // Add current location marker if we have GPS data
        if (data?.gps) {
          this.updateMapLocation(data.gps)
          
          // Initialize heading if available and travelling
          if (data.travelling && data.gps.heading !== undefined) {
            this.rotateCarIcon(data.gps.heading)
          }
        }
        
        // Load existing trip points if available
        if (data?.trip_points && data.trip_points.length > 0) {
          console.log(`📍 Initializing map with ${data.trip_points.length} trip points`)
          window.currentTripPoints = data.trip_points
          this.updateTripPolyline()
        }
        
        // Plot today's completed trips if available
        if (data?.todays_trips && data.todays_trips.trips) {
          this.plotTodaysTrips(data.todays_trips.trips)
        }

        window.mapInitialized = true
        console.log("✅ Dashboard map initialized")

        // Set up update function for async data loading
        window.updateMapWithData = (newData) => {
          if (newData?.gps) {
            this.updateMapLocation(newData.gps)
            if (newData.travelling && newData.gps.heading !== undefined) {
              this.rotateCarIcon(newData.gps.heading)
            }            
          }

          // Load trip points if available
          window.currentTripPoints = newData.trip_points || [];
          if (window.dashboardChannel) {
            window.dashboardChannel.updateTripPolyline();
          }

          // Plot today's completed trips if available
          if (newData?.todays_trips && newData.todays_trips.trips) {
            this.plotTodaysTrips(newData.todays_trips.trips)
          }
        }
      },

      updateMapLocation(gps) {
        if (!window.dashboardMap) return
        
        if (!window.currentMarker) {
          const carIcon = L.divIcon({
            html: `<div class="car-icon-container"><img src="${window.car_icon_path}" alt="car" /></div>`,
            className: 'car-marker',
            iconSize: [32, 32],
            iconAnchor: [16, 16]
          })
          
          window.currentMarker = L.marker([gps.lat, gps.lon], { icon: carIcon })
            .addTo(window.dashboardMap)
        } else {
          window.currentMarker.setLatLng([gps.lat, gps.lon])
        }
        
        // Only update view if we have a reasonable zoom level already
        const currentZoom = window.dashboardMap.getZoom()
        if (currentZoom < 10) {
          window.dashboardMap.setView([gps.lat, gps.lon], 16)
        } else {
          window.dashboardMap.setView([gps.lat, gps.lon], currentZoom)
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
        if (!window.dashboardMap) return

        if (!window.currentTripPoints || window.currentTripPoints.length < 2) {
          if (window.currentTripPolyline) {
            window.dashboardMap.removeLayer(window.currentTripPolyline)
            window.currentTripPolyline = null
          }
          return
        }

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

      plotTodaysTrips(trips) {
        if (!window.dashboardMap || !trips || trips.length === 0) {
          console.log("ℹ️ No trips to plot or map not ready")
          return
        }
        
        console.log(`🗺️ Plotting ${trips.length} completed trip(s) from today`)
        
        // Clear existing completed trips layer if it exists
        if (window.completedTripsLayer) {
          window.dashboardMap.removeLayer(window.completedTripsLayer)
        }
        
        // Create a layer group for completed trips
        window.completedTripsLayer = L.layerGroup().addTo(window.dashboardMap)
        
        trips.forEach((trip, index) => {
          if (!trip.coordinates || trip.coordinates.length < 2) {
            console.log(`⚠️ Trip ${index + 1} has insufficient coordinates`)
            return
          }
          
          // Create polyline for this trip with a different color than current trip
          const tripPolyline = L.polyline(trip.coordinates, {
            color: '#28a745', // Green for completed trips
            weight: 3,
            opacity: 0.6
          })
          
          // Add popup with trip info
          const popupContent = `
            <div style="min-width: 200px;">
              <h6 class="mb-2">${trip.name || 'Trip ' + (index + 1)}</h6>
              <small class="d-block mb-1">
                <i class="bi bi-clock"></i> ${trip.duration_minutes} min
              </small>
              <small class="d-block mb-1">
                <i class="bi bi-speedometer"></i> ${trip.distance_km} km
              </small>
              <small class="d-block">
                <i class="bi bi-arrow-up-circle"></i> ${trip.avg_speed_kmh} km/h avg
              </small>
            </div>
          `
          
          tripPolyline.bindPopup(popupContent)
          window.completedTripsLayer.addLayer(tripPolyline)
        })
        
        console.log(`✅ Plotted ${trips.length} completed trip(s)`)
      },

      initGPSCollapse() {
        // Find the widget header - this is the clickable trigger
        const header = document.querySelector('.gps-widget .widget-header.clickable')
        const content = document.querySelector('.gps-widget .gps-details')
        const icon = document.querySelector('.gps-widget .collapse-icon')
        
        console.log('🔍 GPS Collapse Init - Elements found:', {
          header: !!header,
          content: !!content,
          icon: !!icon
        })
        
        if (!header || !content) {
          console.warn("⚠️ GPS collapse elements not found, will retry...")
          // Retry after a short delay if elements aren't ready yet
          setTimeout(() => this.initGPSCollapse(), 500)
          return
        }
        
        console.log("📍 Initializing GPS collapse functionality")
        
        // Remove any existing listeners to prevent duplicates
        const newHeader = header.cloneNode(true)
        header.parentNode.replaceChild(newHeader, header)
        
        newHeader.addEventListener('click', (e) => {
          e.preventDefault()
          e.stopPropagation()
          
          const isExpanded = content.classList.contains('expanded')
          
          console.log(`📍 GPS widget clicked, currently ${isExpanded ? 'expanded' : 'collapsed'}`)
          
          if (isExpanded) {
            content.classList.remove('expanded')
            content.classList.add('collapsed')
            if (icon) icon.classList.remove('expanded')
            console.log('📍 GPS info collapsed')
          } else {
            content.classList.remove('collapsed')
            content.classList.add('expanded')
            if (icon) icon.classList.add('expanded')
            console.log('📍 GPS info expanded')
          }
        })
        
        console.log("✅ GPS collapse functionality initialized")
      },

      startConnectionMonitor() {
        // Clear any existing monitor
        if (this.connectionMonitorInterval) {
          clearInterval(this.connectionMonitorInterval)
        }
        
        console.log("⏱️ Starting connection monitor (checks every 30 seconds)")
        
        this.connectionMonitorInterval = setInterval(() => {
          const now = Date.now()
          const lastUpdate = window.lastTelemetryUpdate || now
          const secondsSinceUpdate = Math.floor((now - lastUpdate) / 1000)
          const isStale = (now - lastUpdate) > 5 * 60 * 1000 // 5 minutes
          
          console.log(`🔍 Connection check: ${secondsSinceUpdate}s since last update, stale: ${isStale}`)
          
          if (isStale && window.lastTelemetryUpdate) {
            console.log("⚠️ Data is stale (>5 minutes), setting status to Not Connected")
            this.updateTravellingStatus(false)
          }
        }, 30000) // Check every 30 seconds
      },

      stopConnectionMonitor() {
        if (this.connectionMonitorInterval) {
          clearInterval(this.connectionMonitorInterval)
          this.connectionMonitorInterval = null
        }
      }
    })
    
    console.log("📺 Dashboard channel created")
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