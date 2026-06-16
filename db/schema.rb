# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_16_061738) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "dogs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_dogs_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "city", null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "postcode", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "walks", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "accepted_by_walker_id"
    t.datetime "cancelled_at"
    t.string "city", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "dog_id", null: false
    t.bigint "owner_id", null: false
    t.string "postcode"
    t.datetime "started_at"
    t.string "state", default: "requested", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_by_walker_id"], name: "index_walks_on_accepted_by_walker_id"
    t.index ["dog_id"], name: "index_walks_on_dog_id"
    t.index ["owner_id"], name: "index_walks_on_owner_id"
    t.index ["state", "city"], name: "index_walks_on_state_and_city"
    t.check_constraint "(state::text = ANY (ARRAY['requested'::character varying::text, 'cancelled'::character varying::text])) AND accepted_by_walker_id IS NULL OR (state::text = ANY (ARRAY['accepted'::character varying::text, 'in_progress'::character varying::text, 'completed'::character varying::text])) AND accepted_by_walker_id IS NOT NULL", name: "walks_walker_presence"
    t.check_constraint "state::text = ANY (ARRAY['requested'::character varying::text, 'accepted'::character varying::text, 'in_progress'::character varying::text, 'completed'::character varying::text, 'cancelled'::character varying::text])", name: "walks_state_valid"
  end

  add_foreign_key "dogs", "users", on_delete: :restrict
  add_foreign_key "sessions", "users"
  add_foreign_key "walks", "dogs", on_delete: :restrict
  add_foreign_key "walks", "users", column: "accepted_by_walker_id", on_delete: :restrict
  add_foreign_key "walks", "users", column: "owner_id", on_delete: :restrict
end
