import { Controller } from "@hotwired/stimulus"

// Long text collapsed to a preview with a "see more" toggle. Without JS the
// text simply shows in full, so nothing is ever hidden from a visitor who
// cannot run this. A text only a line or two over the limit is left whole: a
// toggle for one hidden line is worse than the line.
export default class extends Controller {
  static targets = ["body", "button"]
  static values = { lines: { type: Number, default: 9 }, more: String, less: String }

  connect() {
    this.expanded = false
    this.measure()
    // Web fonts change line breaks once loaded, so measure again then.
    document.fonts?.ready.then(() => this.measure())
  }

  measure() {
    this.bodyTarget.classList.remove("is-clamped")
    const lineHeight = parseFloat(getComputedStyle(this.bodyTarget).lineHeight)
    const lines = this.bodyTarget.scrollHeight / lineHeight
    this.clampable = lines > this.linesValue + 1
    this.bodyTarget.style.setProperty("--clamp-lines", this.linesValue)
    this.buttonTarget.hidden = !this.clampable
    this.render(!this.expanded)
  }

  toggle() {
    this.expanded = !this.expanded
    this.render(!this.expanded)
  }

  render(clamped) {
    this.bodyTarget.classList.toggle("is-clamped", clamped && this.clampable)
    this.buttonTarget.textContent = clamped ? this.moreValue : this.lessValue
    this.buttonTarget.setAttribute("aria-expanded", String(!clamped))
  }
}
