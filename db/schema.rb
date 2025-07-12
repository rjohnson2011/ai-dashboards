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

ActiveRecord::Schema[8.0].define(version: 2025_07_12_182425) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "check_runs", force: :cascade do |t|
    t.bigint "pull_request_id", null: false
    t.string "name"
    t.string "status"
    t.string "url"
    t.text "description"
    t.boolean "required"
    t.string "suite_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_id", "suite_name"], name: "index_check_runs_on_pull_request_id_and_suite_name"
    t.index ["pull_request_id"], name: "index_check_runs_on_pull_request_id"
    t.index ["required"], name: "index_check_runs_on_required"
    t.index ["status"], name: "index_check_runs_on_status"
  end

  create_table "pull_requests", force: :cascade do |t|
    t.bigint "github_id"
    t.integer "number"
    t.string "title"
    t.string "author"
    t.string "state"
    t.boolean "draft"
    t.string "url"
    t.datetime "pr_created_at"
    t.datetime "pr_updated_at"
    t.string "ci_status"
    t.integer "total_checks"
    t.integer "successful_checks"
    t.integer "failed_checks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "check_runs", "pull_requests"
end
