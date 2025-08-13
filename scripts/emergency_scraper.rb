#!/usr/bin/env ruby
# Emergency Scraper - New file to bypass Render's cached auth controller issue
# This is a temporary workaround until we can clear the cron job's Docker cache

require 'logger'
require 'net/http'
require 'json'

# Set up logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

logger.info "Starting Emergency PR Scraper (Temporary workaround for auth controller cache issue)"
logger.info "This script bypasses the cached Docker image problem"

# Just run the fixed scraper
load File.join(File.dirname(__FILE__), 'render_cron_scraper_fixed.rb')