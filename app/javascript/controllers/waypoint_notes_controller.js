import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview"]

  async connect() {
    const { marked } = await import("https://cdn.jsdelivr.net/npm/marked/lib/marked.esm.js")
    this.marked = marked
    this.marked.use({ breaks: true, gfm: true })

    // Render any existing content on load
    this.previewTargets.forEach(preview => {
      const locale = preview.dataset.locale
      const textarea = this.element.querySelector(`textarea[data-locale="${locale}"]`)
      if (textarea?.value) preview.innerHTML = this.marked.parse(textarea.value)
    })
  }

  preview(event) {
    if (!this.marked) {
      setTimeout(() => this.preview(event), 100)
      return
    }

    const locale = event.target.dataset.locale
    const preview = this.previewTargets.find(el => el.dataset.locale === locale)
    if (!preview) return

    const raw = event.target.value
    preview.innerHTML = raw.trim() ? this.marked.parse(raw) : ""
  }
}