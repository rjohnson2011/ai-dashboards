Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Simple health check
  get "health" => proc { [200, {"Content-Type" => "application/json"}, [{status: "ok", version: "1.0.2", auth_removed: true}.to_json]] }

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
      post "admin/initialize_data", to: "admin#initialize_data"
      post "admin/update_data", to: "admin#update_data"
      post "admin/update_full_data", to: "admin#update_full_data"
      post "admin/cleanup_merged_prs", to: "admin#cleanup_merged_prs"
      post "admin/update_checks_via_api", to: "admin#update_checks_via_api"
      get "admin/background_job_logs", to: "admin#background_job_logs"
      get "admin/webhook_events", to: "admin#webhook_events"
      get "admin/debug_token", to: "admin#debug_token"
      get "admin/cron_status", to: "admin#cron_status"

      # GitHub webhook endpoint
      post "github_webhooks", to: "github_webhooks#create"
      
      # Authentication routes - temporarily disabled
      # get "auth/github", to: "auth#github"
      # get "auth/github/callback", to: "auth#github_callback"
      # get "auth/me", to: "auth#me"
      # post "auth/logout", to: "auth#logout"
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
