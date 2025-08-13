#!/bin/bash
# Standalone scraper that bypasses Rails initialization
# This is a temporary workaround for Render's cached Docker image issue

echo "Starting standalone scraper (bypassing Rails initialization issue)"
echo "Current directory: $(pwd)"
echo "Checking for auth_controller.rb..."

# Check if the problematic file exists
if [ -f "app/controllers/api/v1/auth_controller.rb" ]; then
    echo "ERROR: auth_controller.rb exists - this shouldn't happen!"
    exit 1
fi

if [ -f "src/app/controllers/api/v1/auth_controller.rb" ]; then
    echo "ERROR: Old src/ structure detected - using cached Docker image!"
    echo "This cron job needs to be deleted and recreated."
    exit 1
fi

# If we get here, try to run the actual scraper
echo "No auth_controller.rb found (good!), attempting to run scraper..."
bundle exec rails runner scripts/render_cron_scraper_fixed.rb