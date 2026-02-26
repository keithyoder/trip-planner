import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button", "icon"]

  copy() {
    navigator.clipboard.writeText(this.activeContent).then(() => {
      this.iconTarget.classList.replace("bi-clipboard", "bi-clipboard-check")
      setTimeout(() => {
        this.iconTarget.classList.replace("bi-clipboard-check", "bi-clipboard")
      }, 2000)
    })
  }

  get activeContent() {
    // If there's only one source target, use it directly
    if (this.sourceTargets.length === 1) {
      return this.sourceTargets[0].dataset.content
    }

    // Otherwise find the active tab pane
    const active = this.sourceTargets.find(el => el.classList.contains("active"))
    return (active ?? this.sourceTargets[0]).dataset.content
  }
}