#!/bin/bash

echo "Updating localhost PR data..."

# Quick update to refresh PR list and last updated time
bundle exec rake dev:quick_update

echo ""
echo "To run full updates with checks (takes longer):"
echo "  bundle exec rake dev:run_updates"
echo ""
echo "To start automatic updates every 15 minutes:"
echo "  bundle exec rake dev:scheduler"