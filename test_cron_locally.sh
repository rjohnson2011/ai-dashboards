#!/bin/bash
# Test the cron job scraper locally

echo "Testing Render cron job scraper locally..."
echo "========================================"

# Set Rails environment
export RAILS_ENV=development

# Run the scraper
bundle exec rails runner scripts/render_cron_scraper.rb

echo ""
echo "Test complete!"
echo "If successful, commit and push to deploy the cron job."