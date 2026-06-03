class CreateDogs < ActiveRecord::Migration[8.1]
  def change
    # The entity the marketplace orbits — a dog owned by a User (the Owner).
    # Soft-deleted via deactivated_at so removal never destroys walk history
    # (resolves Open Q #4 toward soft-delete; FK is RESTRICT, never cascade).
    create_table :dogs do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: { on_delete: :restrict }
      t.datetime :deactivated_at # nullable: NULL = active

      t.timestamps
    end
  end
end
