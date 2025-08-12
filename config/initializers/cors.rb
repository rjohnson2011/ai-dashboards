# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # In production, be more specific with your origins
    origins "http://localhost:5173",
            "http://localhost:5174",
            "https://platform-code-reviews-frontend.onrender.com",
            "https://ai-dashboards-frontend.vercel.app",
            "https://vetsapi-pr-review.vercel.app",
            /https:\/\/.*\.onrender\.com/,
            /https:\/\/.*\.vercel\.app/

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      expose: [ "Authorization" ],
      credentials: true
  end
end
