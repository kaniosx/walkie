class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :dogs, dependent: :restrict_with_exception
  has_many :owned_walks, class_name: "Walk", foreign_key: :owner_id, dependent: :restrict_with_exception
  has_many :accepted_walks, class_name: "Walk", foreign_key: :accepted_by_walker_id, dependent: :restrict_with_exception

  # Binding account type, chosen at registration. A user is Owner XOR Walker;
  # dual-role and role switching are out of scope (PRD §Access Control).
  enum :role, { owner: "owner", walker: "walker" }

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  # Coarse free-text locality (PRD §Open Q #6); strip surrounding whitespace
  # only — no case/format change. display_name is trimmed too when present.
  normalizes :city, with: ->(v) { v.strip }
  normalizes :display_name, with: ->(v) { v.strip.presence }

  validates :role, presence: true
  # city is required (collected at sign-up); display_name is optional.
  validates :city, presence: true, length: { maximum: 100 }
  validates :display_name, length: { maximum: 100 }, allow_nil: true
  validate :role_is_immutable, on: :update

  # Name to show in the UI: the chosen display name, or the email when unset.
  def display_label
    display_name.presence || email_address
  end

  private
    # Enforce "no role switching" outside the UI: once persisted, role is fixed.
    def role_is_immutable
      errors.add(:role, "cannot be changed after registration") if role_changed?
    end
end
