import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hamburger", "menu"]

  toggle() {
    const expanded = this.hamburgerTarget.getAttribute("aria-expanded") === "true"
    this.hamburgerTarget.setAttribute("aria-expanded", String(!expanded))
    this.menuTarget.classList.toggle("hidden")
  }

  closeOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  close() {
    if (this.hasHamburgerTarget) {
      this.hamburgerTarget.setAttribute("aria-expanded", "false")
      this.hamburgerTarget.focus()
    }
    if (this.hasMenuTarget) this.menuTarget.classList.add("hidden")
  }
}
