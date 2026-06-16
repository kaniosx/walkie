class Dog < ApplicationRecord
  belongs_to :user

  # Walk history is never cascade-deleted — soft-delete the dog instead
  # (see deactivate!), so completed/in-flight walks survive removal.
  has_many :walks, dependent: :restrict_with_exception

  # Strip surrounding whitespace on the free-text fields (consistent with User).
  normalizes :name, with: ->(v) { v.strip }
  normalizes :breed, with: ->(v) { v.strip }

  validates :name, presence: true, length: { maximum: 100 }
  # breed is required (collected at creation); weight is optional kilograms,
  # a positive bounded integer when present; notes is free-form.
  validates :breed, presence: true, length: { maximum: 100 }
  validates :weight, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }, allow_nil: true
  validates :notes, length: { maximum: 1000 }, allow_nil: true

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
