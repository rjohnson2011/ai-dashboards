#!/usr/bin/env bash
# exit on error
set -o errexit

bundle install

# Don't run any database tasks during build
# Render will run migrations automatically after the database is connected