import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    const button = this.element.querySelector("[data-nav-hamburger]")
    const expanded = button.getAttribute("aria-expanded") === "true"
    button.setAttribute("aria-expanded", String(!expanded))
    this.menuTarget.classList.toggle("hidden")
  }

  closeOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  close() {
    const button = this.element.querySelector("[data-nav-hamburger]")
    if (button) button.setAttribute("aria-expanded", "false")
    if (this.hasMenuTarget) this.menuTarget.classList.add("hidden")
  }
}
