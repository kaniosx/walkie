import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!("geolocation" in navigator)) {
      this.showError("Your browser doesn't support location. Open requests need it.")
      return
    }

    navigator.geolocation.getCurrentPosition(
      (position) => this.locationGranted(position),
      () => this.showError("Location access is required to see open walk requests. Please allow location access and try again.")
    )
  }

  locationGranted(position) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("lat", position.coords.latitude)
    url.searchParams.set("lng", position.coords.longitude)
    this.element.src = url.toString()
  }

  showError(message) {
    this.element.innerHTML = ""
    const notice = document.createElement("p")
    notice.className = "bg-white rounded-xl shadow-sm ring-1 ring-stone-200 p-6 text-center text-stone-500"
    notice.textContent = message
    this.element.appendChild(notice)
  }
}
