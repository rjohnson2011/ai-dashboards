Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    namespace :v1 do
      resources :repositories, only: [ :index ]
      resources :reviews, only: [ :index ]
      get "pull_requests/:number", to: "reviews#show"
      get "pull_requests/:number/timeline", to: "reviews#timeline"
      get "reviews/status", to: "reviews#status"
      post "reviews/refresh", to: "reviews#refresh"
      get "reviews/historical", to: "reviews#historical"
      get "reviews/version", to: "reviews#version"
      post "admin/initialize_data", to: "admin#initialize_data"
      post "admin/update_data", to: "admin#update_data"
      post "admin/update_full_data", to: "admin#update_full_data"
      post "admin/cleanup_merged_prs", to: "admin#cleanup_merged_prs"
      post "admin/update_checks_via_api", to: "admin#update_checks_via_api"
      get "admin/background_job_logs", to: "admin#background_job_logs"
      get "admin/webhook_events", to: "admin#webhook_events"
      get "admin/debug_token", to: "admin#debug_token"
      get "admin/cron_status", to: "admin#cron_status"
      post "admin/run_task", to: "admin#run_task"
      post "admin/manual_scraper_run", to: "admin#manual_scraper_run"
      get "admin/verify_scraper_version", to: "admin#verify_scraper_version"
      get "admin/backend_members", to: "admin#backend_members"
      post "admin/refresh_backend_members", to: "admin#refresh_backend_members"
      get "admin/debug_pr", to: "admin#debug_pr"
      post "admin/fix_all_pr_statuses", to: "admin#fix_all_pr_statuses"
      post "admin/verify_pr_accuracy", to: "admin#verify_pr_accuracy"
      post "admin/remove_repository_prs", to: "admin#remove_repository_prs"
      post "admin/fetch_reviews", to: "admin#fetch_reviews"
      post "admin/fetch_ci_checks", to: "admin#fetch_ci_checks"
      post "admin/run_migrations", to: "admin#run_migrations"
      get "health", to: "admin#health"

      # GitHub webhook endpoint
      post "github_webhooks", to: "github_webhooks#create"

      # Sprint metrics endpoints
      get "sprint_metrics", to: "sprint_metrics#index"
      get "sprint_metrics/detailed", to: "sprint_metrics#detailed"
      get "sprint_metrics/review_turnaround", to: "sprint_metrics#review_turnaround"
      get "sprint_metrics/support_rotations", to: "sprint_metrics#support_rotations"
      post "sprint_metrics/support_rotations", to: "sprint_metrics#create_support_rotation"
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
