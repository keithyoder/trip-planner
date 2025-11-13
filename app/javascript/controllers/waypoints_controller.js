// app/javascript/controllers/waypoints_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["group", "tableRow", "filter", "map", "timeline", "grouped"]
  static values = {
    activeTypes: { type: Array, default: [] }
  }

  connect() {
    console.log("🎯 Waypoints controller connected")
    this.initializeFilters()
  }

  initializeFilters() {
    // Get all waypoint types from the page
    const allTypes = new Set()
    this.filterTargets.forEach(filter => {
      allTypes.add(filter.dataset.waypointType)
    })
    this.activeTypesValue = Array.from(allTypes)
  }

  toggleType(event) {
    const checkbox = event.target
    const type = checkbox.dataset.waypointType
    
    if (checkbox.checked) {
      this.showType(type)
    } else {
      this.hideType(type)
    }
  }

  showType(type) {
    // Show card group
    const group = this.groupTargets.find(g => g.dataset.waypointGroup === type)
    if (group) {
      group.classList.remove('d-none')
      group.style.display = 'block'
    }

    // Show table rows
    this.tableRowTargets
      .filter(row => row.dataset.waypointType === type)
      .forEach(row => {
        row.classList.remove('d-none')
        row.style.display = ''
      })

    // Update active types
    if (!this.activeTypesValue.includes(type)) {
      this.activeTypesValue = [...this.activeTypesValue, type]
    }
  }

  hideType(type) {
    // Hide card group
    const group = this.groupTargets.find(g => g.dataset.waypointGroup === type)
    if (group) {
      group.classList.add('d-none')
      group.style.display = 'none'
    }

    // Hide table rows
    this.tableRowTargets
      .filter(row => row.dataset.waypointType === type)
      .forEach(row => {
        row.classList.add('d-none')
        row.style.display = 'none'
      })

    // Update active types
    this.activeTypesValue = this.activeTypesValue.filter(t => t !== type)
  }

  showAll(event) {
    event.preventDefault()
    this.filterTargets.forEach(filter => {
      filter.checked = true
      this.showType(filter.dataset.waypointType)
    })
  }

  hideAll(event) {
    event.preventDefault()
    this.filterTargets.forEach(filter => {
      filter.checked = false
      this.hideType(filter.dataset.waypointType)
    })
  }

  highlightWaypoint(event) {
    const waypointId = event.currentTarget.dataset.waypointId
    
    // Remove previous highlights
    document.querySelectorAll('[data-waypoint-id]').forEach(el => {
      el.classList.remove('border-primary', 'border-2', 'border-start')
    })

    // Add highlight to current
    event.currentTarget.classList.add('border-primary', 'border-2', 'border-start')

    // Dispatch custom event for map controller to handle
    const mapEvent = new CustomEvent('waypoint:highlight', {
      detail: { waypointId: waypointId },
      bubbles: true
    })
    this.element.dispatchEvent(mapEvent)
  }

  expandAll(event) {
    event.preventDefault()
    this.groupTargets.forEach(group => {
      const collapseElement = group.querySelector('.collapse')
      if (collapseElement && !collapseElement.classList.contains('show')) {
        new bootstrap.Collapse(collapseElement, { toggle: true })
      }
    })
  }

  collapseAll(event) {
    event.preventDefault()
    this.groupTargets.forEach(group => {
      const collapseElement = group.querySelector('.collapse')
      if (collapseElement && collapseElement.classList.contains('show')) {
        new bootstrap.Collapse(collapseElement, { toggle: true })
      }
    })
  }

  showTimelineView(event) {
    if (this.hasTimelineTarget && this.hasGroupedTarget) {
      this.timelineTarget.classList.remove('d-none')
      this.groupedTarget.classList.add('d-none')
    }
  }

  showGroupedView(event) {
    if (this.hasTimelineTarget && this.hasGroupedTarget) {
      this.timelineTarget.classList.add('d-none')
      this.groupedTarget.classList.remove('d-none')
    }
  }
}