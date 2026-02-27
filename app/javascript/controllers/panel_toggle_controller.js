import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dayPlan", "directions"]
  static values = { locale: String }

  connect() {
    this.showDayPlan()
    this.activateLocaleTab()
  }

  showDayPlan() {
    this.dayPlanTarget.classList.remove('d-none')
    this.directionsTarget.classList.add('d-none')
    this.updateButtons('day-plan')
  }

  showDirections() {
    this.directionsTarget.classList.remove('d-none')
    this.dayPlanTarget.classList.add('d-none')
    this.updateButtons('directions')
  }

  updateButtons(active) {
    this.element.querySelectorAll('[data-panel]').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.panel === active)
    })
  }

  activateLocaleTab() {
    const locale = this.localeValue
    const tab = this.element.querySelector(`#day-plan-tab-${locale}`)
    if (!tab) return

    // Deactivate all tabs and panes
    this.element.querySelectorAll('.nav-link').forEach(t => t.classList.remove('active'))
    this.element.querySelectorAll('.tab-pane').forEach(p => {
      p.classList.remove('show', 'active')
    })

    // Activate the matching tab and pane
    tab.classList.add('active')
    const pane = this.element.querySelector(`#day-plan-${locale}`)
    if (pane) pane.classList.add('show', 'active')
  }
}