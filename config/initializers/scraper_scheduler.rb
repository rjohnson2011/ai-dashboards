# frozen_string_literal: true

# In-process scraper scheduler.
#
# The scraper used to be driven solely by the `schedule:` trigger on the
# PR Scraper Cron GitHub Actions workflow. That trigger is best-effort: GitHub
# sheds scheduled workflows under load, and on 2026-08-27 it degraded from ~15
# dispatches/day to 7, to 1, then stopped for 17 hours while every run that did
# fire succeeded. A watchdog workflow added to catch that was itself throttled
# within two hours, because it shares the same failure mode.
#
# This service already runs 24/7 on Render, so it can schedule itself and take
# GitHub's scheduler off the critical path entirely. The GitHub workflow stays in
# place as redundancy — whichever fires first wins, and the loser is a cheap
# no-op because the scrape is idempotent.
#
# Design notes:
#
# * Runs only in the Puma web process (`SCRAPER_SCHEDULER=enabled`), never in
#   rake tasks, console sessions, or one-off jobs, so a `rails console` cannot
#   start a second scheduler.
# * `WEB_CONCURRENCY` is 1 on this service, so there is a single worker and a
#   single scheduler thread. If concurrency is ever raised, only worker 0 should
#   run this — see the worker-index guard below.
# * Each cycle is wrapped so a scrape failure logs and the loop survives; a
#   dead scheduler thread would be a silent outage of exactly the kind this
#   exists to prevent.
# * Writes CronJobLog on both success and failure, which is what
#   ReviewsController#sync_health measures staleness from.

module ScraperScheduler
  # Matches the cadence the GitHub workflow targets.
  INTERVAL = 15.minutes

  # 13:00–23:00 UTC Mon–Fri, matching pr-scraper.yml. Covers 9am–7pm ET across
  # both DST offsets.
  ACTIVE_HOURS_UTC = (13..23)
  ACTIVE_DAYS = (1..5) # Monday–Friday

  # Same repositories, in the same order, as the GitHub workflow.
  REPOSITORIES = %w[vets-api vets-api-mockdata platform-atlas].freeze
  OWNER = "software"

  # Give Rails a moment to finish booting before the first scrape.
  STARTUP_DELAY = 60.seconds

  module_function

  def within_active_window?(now = Time.current.utc)
    ACTIVE_DAYS.cover?(now.wday) && ACTIVE_HOURS_UTC.cover?(now.hour)
  end

  # True when the data is already fresh enough that a scrape would be wasted
  # work. Uses the same signal sync_health reports, so the scheduler and the
  # health endpoint can never disagree about what "fresh" means.
  def recently_synced?
    last = CronJobLog.where(status: "completed").order(started_at: :desc).first
    return false if last.nil?

    synced_at = last.completed_at || last.started_at
    synced_at.present? && synced_at > INTERVAL.ago
  rescue => e
    Rails.logger.warn "[ScraperScheduler] Could not read CronJobLog: #{e.message}"
    false
  end

  def run_scrape
    started_at = Time.current
    cron_log = begin
      CronJobLog.create!(status: "running", started_at: started_at)
    rescue => e
      Rails.logger.warn "[ScraperScheduler] Could not create CronJobLog: #{e.message}"
      nil
    end

    begin
      REPOSITORIES.each do |repo|
        Rails.logger.info "[ScraperScheduler] Scraping #{OWNER}/#{repo}..."
        FetchAllPullRequestsJob.perform_now(
          repository_name: repo,
          repository_owner: OWNER,
          lite_mode: false
        )
      end

      cron_log&.update!(status: "completed", completed_at: Time.current)
      Rails.logger.info "[ScraperScheduler] Scrape completed in #{(Time.current - started_at).round(1)}s"
    rescue => e
      Rails.logger.error "[ScraperScheduler] Scrape failed: #{e.class}: #{e.message}"
      begin
        cron_log&.update!(
          status: "failed",
          completed_at: Time.current,
          error_class: e.class.name,
          error_message: e.message,
          error_backtrace: e.backtrace&.first(20)&.join("\n")
        )
      rescue => log_error
        Rails.logger.warn "[ScraperScheduler] Could not record failure: #{log_error.message}"
      end
    end
  end

  def start!
    Thread.new do
      Thread.current.name = "scraper-scheduler"
      sleep STARTUP_DELAY

      loop do
        begin
          if !within_active_window?
            Rails.logger.debug "[ScraperScheduler] Outside active window; skipping."
          elsif recently_synced?
            Rails.logger.debug "[ScraperScheduler] Synced within the last #{INTERVAL.inspect}; skipping."
          else
            run_scrape
          end
        rescue => e
          # The loop must outlive any individual failure.
          Rails.logger.error "[ScraperScheduler] Cycle error: #{e.class}: #{e.message}"
        end

        # Poll more often than the interval so a skipped cycle (outside the
        # window, or already fresh) re-checks promptly rather than waiting a
        # full interval.
        sleep 5.minutes
      end
    end
  end
end

# Started from config/puma.rb's on_worker_boot, NOT here.
#
# `preload_app!` runs initializers in the Puma master before it forks workers, so
# starting a thread at initializer time would create it pre-fork, where it would
# not survive into the workers. on_worker_boot runs post-fork in each worker,
# which is where a background thread has to be created. Defining the module here
# and starting it there also means console sessions and rake tasks load this file
# without ever spawning a scheduler.
