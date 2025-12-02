# frozen_string_literal: true

require "net/http"
require "uri"
require "nokogiri"

class PrHtmlScraperService
  def initialize
    @github_token = ENV["GITHUB_TOKEN"]
  end

  # Scrape the actual PR web page to check for approvals
  def verify_pr_from_html(pr_number, repository_name, repository_owner)
    url = "https://github.com/#{repository_owner}/#{repository_name}/pull/#{pr_number}"

    Rails.logger.info "[PrHtmlScraper] Fetching HTML from #{url}"

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    request["Accept"] = "text/html,application/xhtml+xml,application/xml"

    # Add GitHub token for authenticated requests (higher rate limit)
    request["Authorization"] = "token #{@github_token}" if @github_token

    response = http.request(request)

    unless response.code == "200"
      Rails.logger.error "[PrHtmlScraper] Failed to fetch PR page: #{response.code}"
      return { success: false, error: "HTTP #{response.code}" }
    end

    # Parse HTML
    doc = Nokogiri::HTML(response.body)

    # Find approval indicators in the HTML
    approvals = extract_approvals_from_html(doc)

    {
      success: true,
      pr_number: pr_number,
      approvals_found: approvals,
      url: url
    }

  rescue => e
    Rails.logger.error "[PrHtmlScraper] Error scraping PR ##{pr_number}: #{e.message}"
    { success: false, error: e.message }
  end

  # Verify all PRs in "PRs Needing Team Review" by scraping their HTML
  def verify_prs_needing_review_via_html(repository_name, repository_owner)
    backend_members = BackendReviewGroupMember.pluck(:username)

    # Find PRs categorized as "needing team review"
    needs_review_prs = PullRequest.where(
      state: "open",
      repository_name: repository_name,
      repository_owner: repository_owner
    ).select do |pr|
      pr.backend_approval_status != "approved" &&
      !(pr.approval_summary && pr.approval_summary[:approved_users]&.any? { |user| backend_members.include?(user) }) &&
      !pr.draft &&
      !(pr.labels && pr.labels.include?("exempt-be-review")) &&
      !(pr.approval_summary && pr.approval_summary[:approved_count].to_i > 0)
    end

    Rails.logger.info "[PrHtmlScraper] Found #{needs_review_prs.count} PRs to verify via HTML scraping"

    results = []
    updated_count = 0

    needs_review_prs.each do |pr|
      result = verify_pr_from_html(pr.number, repository_name, repository_owner)

      if result[:success] && result[:approvals_found].any?
        # Found approvals via HTML that weren't in API
        backend_approvals = result[:approvals_found].select { |username| backend_members.include?(username) }

        if backend_approvals.any?
          Rails.logger.warn "[PrHtmlScraper] PR ##{pr.number} has backend approvals in HTML that API missed: #{backend_approvals.join(', ')}"

          # Force re-fetch from API now that we know there are approvals
          github_service = GithubService.new
          reviews = github_service.pull_request_reviews(pr.number)

          # Update reviews
          reviews.each do |review_data|
            PullRequestReview.find_or_create_by(
              pull_request_id: pr.id,
              github_id: review_data.id
            ).update!(
              user: review_data.user.login,
              state: review_data.state,
              submitted_at: review_data.submitted_at
            )
          end

          # Update approval status
          pr.update_backend_approval_status!
          pr.update_ready_for_backend_review!
          pr.update_approval_status!

          updated_count += 1
        end
      end

      results << result

      # Rate limit: sleep between requests
      sleep(2)
    end

    {
      total_checked: needs_review_prs.count,
      updated: updated_count,
      results: results
    }
  end

  private

  def extract_approvals_from_html(doc)
    approvals = []

    # Method 1: Find review status badges/pills
    # GitHub uses elements like: <div class="merge-status-item" data-details-container>
    doc.css(".merge-status-item, .review-status-item, .js-timeline-item").each do |item|
      # Look for "approved" text
      if item.text.include?("approved") || item.text.include?("Approved")
        # Extract username from the item
        username = extract_username_from_element(item)
        approvals << username if username
      end
    end

    # Method 2: Find timeline review events
    doc.css('[data-testid="pr-timeline-review-event"]').each do |event|
      if event.text.include?("approved")
        username = extract_username_from_element(event)
        approvals << username if username
      end
    end

    # Method 3: Look for approval checkmarks in review section
    doc.css(".TimelineItem-badge").each do |badge|
      if badge["title"]&.include?("approved") || badge.css(".octicon-check").any?
        # Find associated username
        timeline_item = badge.ancestors(".TimelineItem").first
        if timeline_item
          username = extract_username_from_element(timeline_item)
          approvals << username if username
        end
      end
    end

    # Method 4: Find in "Reviewers" sidebar
    doc.css(".discussion-sidebar-item .reviewer").each do |reviewer|
      if reviewer.text.include?("approved") || reviewer.css(".octicon-check").any?
        username = reviewer.css("a").first&.text&.strip&.gsub("@", "")
        approvals << username if username
      end
    end

    approvals.compact.uniq
  end

  def extract_username_from_element(element)
    # Try to find username in various places
    username = nil

    # Look for author link
    author_link = element.css("a.author, a[data-hovercard-type=\"user\"]").first
    username = author_link&.text&.strip&.gsub("@", "") if author_link

    # Look for data attributes
    username ||= element["data-actor"] || element["data-user"]

    # Look in alt text of avatar images
    if !username
      img = element.css("img.avatar").first
      username = img["alt"]&.gsub("@", "") if img
    end

    username&.strip
  end
end
