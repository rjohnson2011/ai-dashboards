# Pre-builds the payload returned by /api/v1/reviews and stores it in
# Rails.cache, so the controller can return it instantly without doing
# a full DB traversal on every request.
#
# Called at the end of every scraper job. Writes one cache entry for the
# "all repos" view (which is what the dashboard frontends use) — that
# covers ~100% of real traffic.
class RefreshReviewsCacheService
  CACHE_KEY = "prebuilt_reviews:all"
  TTL = 24.hours

  def self.call
    payload = BuildReviewsPayloadService.call
    Rails.cache.write(CACHE_KEY, payload, expires_in: TTL)
    Rails.logger.info "[RefreshReviewsCacheService] Cached prebuilt /reviews payload (#{payload[:count] + payload[:approved_count]} PRs)"
    payload
  rescue StandardError => e
    Rails.logger.error "[RefreshReviewsCacheService] Failed: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    nil
  end
end
