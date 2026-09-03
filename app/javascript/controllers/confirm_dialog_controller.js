import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["dialog", "message", "confirmButton"]

  connect() {
    Turbo.config.forms.confirm = (message, formElement, submitter) => this.confirm(message, submitter)
    this.dialogTarget.addEventListener("click", (event) => {
      if (event.target === this.dialogTarget) this.dialogTarget.close()
    })
  }

  confirm(message, submitter) {
    this.messageTarget.textContent = message
    this.applyVariant(submitter?.dataset.turboConfirmStyle === "danger")
    this.dialogTarget.showModal()

    return new Promise((resolve) => {
      this.dialogTarget.addEventListener(
        "close",
        () => resolve(this.dialogTarget.returnValue === "confirm"),
        { once: true }
      )
    })
  }

  applyVariant(isDanger) {
    this.confirmButtonTarget.classList.toggle("bg-red-600", isDanger)
    this.confirmButtonTarget.classList.toggle("hover:bg-red-700", isDanger)
    this.confirmButtonTarget.classList.toggle("bg-primary-600", !isDanger)
    this.confirmButtonTarget.classList.toggle("hover:bg-primary-700", !isDanger)
  }
}
