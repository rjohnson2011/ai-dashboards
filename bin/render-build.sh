#!/usr/bin/env bash
# exit on error
set -o errexit

bundle install

# Run migrations as part of the build. Render does NOT do this automatically:
# this service is a ruby-runtime service whose startCommand is a bare puma, so
# without this line a deploy ships code ahead of its schema and every request
# touching a new column fails with "unknown attribute" until someone migrates
# by hand. errexit above means a failed migration fails the deploy, which is
# what we want — better than booting against a schema the code can't use.
bundle exec rake db:migrate
