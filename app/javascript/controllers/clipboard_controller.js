import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button", "icon"]

  copy() {
    navigator.clipboard.writeText(this.sourceTarget.dataset.content).then(() => {
      this.iconTarget.classList.replace("bi-clipboard", "bi-clipboard-check")
      setTimeout(() => {
        this.iconTarget.classList.replace("bi-clipboard-check", "bi-clipboard")
      }, 2000)
    })
  }
}