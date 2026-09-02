import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["latitude", "longitude", "submit"]

  connect() {
    if (!("geolocation" in navigator)) {
      this.showError("Your browser doesn't support location. A walk request needs it.")
      return
    }

    navigator.geolocation.getCurrentPosition(
      (position) => this.locationGranted(position),
      () => this.showError("Location access is required to request a walk. Please allow location access and try again.")
    )
  }

  locationGranted(position) {
    this.latitudeTarget.value = position.coords.latitude
    this.longitudeTarget.value = position.coords.longitude
    this.submitTarget.disabled = false
  }

  showError(message) {
    const notice = document.createElement("p")
    notice.className = "text-sm text-red-600"
    notice.textContent = message
    this.submitTarget.replaceWith(notice)
  }
}
