class AddDetailsToDogs < ActiveRecord::Migration[8.1]
  def up
    # breed is required (collected when the owner adds a dog); weight (kg) and
    # notes are optional. Add nullable first so the column lands on the
    # populated table, backfill pre-existing rows (dev/test only — no real
    # users yet per roadmap baseline), then enforce NOT NULL on breed.
    add_column :dogs, :breed, :string
    add_column :dogs, :weight, :integer
    add_column :dogs, :notes, :text

    Dog.reset_column_information
    Dog.where(breed: nil).update_all(breed: "Unknown")

    change_column_null :dogs, :breed, false
  end

  def down
    remove_column :dogs, :notes
    remove_column :dogs, :weight
    remove_column :dogs, :breed
  end
end
