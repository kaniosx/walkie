class Dog < ApplicationRecord
  belongs_to :user

  # Walk history is never cascade-deleted — soft-delete the dog instead
  # (see deactivate!), so completed/in-flight walks survive removal.
  has_many :walks, dependent: :restrict_with_exception

  validates :name, presence: true

  # Explicit active-only scope instead of a default_scope. A default_scope on
  # soft-delete is a known foot-gun (leaks into associations, unscoped
  # surprises); User establishes the no-magic-scoping precedent.
  scope :active, -> { where(deactivated_at: nil) }

  # Soft-delete: stamp deactivated_at so the row (and its walks) persist but
  # the dog drops out of Dog.active.
  def deactivate!
    update!(deactivated_at: Time.current)
  end

  def active?
    deactivated_at.nil?
  end
end
