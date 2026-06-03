class CreateWalks < ActiveRecord::Migration[8.1]
  def change
    # The walk request and its linear state machine. Every invariant that must
    # hold "outside the UI" (PRD §Guardrails) is enforced here at the DB level:
    # FKs, valid-state membership, and the state <-> walker consistency check.
    create_table :walks do |t|
      t.references :dog, null: false, foreign_key: { on_delete: :restrict }
      # owner_id is denormalized (= dog.user_id) so open-request queries never
      # need to join dogs; Walk validates the two stay consistent.
      t.references :owner, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      # NULL until a Walker accepts; the walker-presence CHECK ties this to state.
      t.references :accepted_by_walker, null: true, foreign_key: { to_table: :users, on_delete: :restrict }

      t.string :state, null: false, default: "requested"

      # Locality snapshot taken at creation (S-04 wires it to the profile field).
      t.string :city, null: false
      t.string :postcode

      # Per-transition timestamps, each stamped by its transition method.
      t.datetime :accepted_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :cancelled_at

      t.timestamps
    end

    # Serves S-05's "open requests in my city" filter (state = 'requested' AND city = ?).
    add_index :walks, [ :state, :city ]

    # Only the five legal states may ever persist.
    add_check_constraint :walks,
      "state IN ('requested','accepted','in_progress','completed','cancelled')",
      name: "walks_state_valid"

    # The load-bearing invariant: a walker is bound exactly when the walk has
    # left the unaccepted states. Both directions in one CHECK make an
    # inconsistent shape impossible to persist even via raw SQL / update_all.
    add_check_constraint :walks,
      "(state IN ('requested','cancelled') AND accepted_by_walker_id IS NULL) " \
      "OR (state IN ('accepted','in_progress','completed') AND accepted_by_walker_id IS NOT NULL)",
      name: "walks_walker_presence"
  end
end
