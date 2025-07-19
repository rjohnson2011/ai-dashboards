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

ActiveRecord::Schema[8.0].define(version: 2025_07_19_043252) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "backend_review_group_members", force: :cascade do |t|
    t.string "username"
    t.string "avatar_url"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_backend_review_group_members_on_username"
  end

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

  create_table "daily_snapshots", force: :cascade do |t|
    t.date "snapshot_date", null: false
    t.integer "total_prs", default: 0
    t.integer "approved_prs", default: 0
    t.integer "prs_with_changes_requested", default: 0
    t.integer "pending_review_prs", default: 0
    t.integer "draft_prs", default: 0
    t.integer "failing_ci_prs", default: 0
    t.integer "successful_ci_prs", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["snapshot_date"], name: "index_daily_snapshots_on_snapshot_date", unique: true
  end

  create_table "pull_request_reviews", force: :cascade do |t|
    t.bigint "pull_request_id", null: false
    t.bigint "github_id"
    t.string "user"
    t.string "state"
    t.text "body"
    t.datetime "submitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_id"], name: "index_pull_request_reviews_on_github_id", unique: true
    t.index ["pull_request_id"], name: "index_pull_request_reviews_on_pull_request_id"
    t.index ["state"], name: "index_pull_request_reviews_on_state"
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
    t.string "backend_approval_status", default: "not_approved"
    t.boolean "ready_for_backend_review", default: false
    t.datetime "approved_at"
    t.index ["backend_approval_status"], name: "index_pull_requests_on_backend_approval_status"
    t.index ["github_id"], name: "index_pull_requests_on_github_id", unique: true
  end

  add_foreign_key "check_runs", "pull_requests"
  add_foreign_key "pull_request_reviews", "pull_requests"
end
