#!/usr/bin/env bash
# exit on error
set -o errexit

bundle install

# Only run database tasks if DATABASE_URL is set
if [[ -n "$DATABASE_URL" ]]; then
  bundle exec rake db:create || true
  bundle exec rake db:migrate
  bundle exec rake db:seed || true
fi