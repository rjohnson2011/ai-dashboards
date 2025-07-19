Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    namespace :v1 do
      resources :reviews, only: [:index]
      get 'pull_requests/:number', to: 'reviews#show'
      get 'reviews/status', to: 'reviews#status'
      post 'reviews/refresh', to: 'reviews#refresh'
      get 'reviews/historical', to: 'reviews#historical'
      post 'admin/initialize_data', to: 'admin#initialize_data'
      post 'admin/update_data', to: 'admin#update_data'
      post 'admin/update_full_data', to: 'admin#update_full_data'
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
