class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :dogs, dependent: :restrict_with_exception

  # Binding account type, chosen at registration. A user is Owner XOR Walker;
  # dual-role and role switching are out of scope (PRD §Access Control).
  enum :role, { owner: "owner", walker: "walker" }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :role, presence: true
  validate :role_is_immutable, on: :update

  private
    # Enforce "no role switching" outside the UI: once persisted, role is fixed.
    def role_is_immutable
      errors.add(:role, "cannot be changed after registration") if role_changed?
    end
end
