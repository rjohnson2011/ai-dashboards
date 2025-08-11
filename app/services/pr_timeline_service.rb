class PrTimelineService
  def initialize(owner: nil, repo: nil)
    @github_service = GithubService.new(owner: owner, repo: repo)
    @client = @github_service.instance_variable_get(:@client)
    @owner = owner || @github_service.instance_variable_get(:@owner)
    @repo = repo || @github_service.instance_variable_get(:@repo)
  end

  def get_recent_timeline(pr_number, limit = 5)
    activities = []

    begin
      # Get comments
      comments = @client.issue_comments("#{@owner}/#{@repo}", pr_number, per_page: 10, direction: "desc")
      comments.each do |comment|
        activities << {
          type: "comment",
          time: comment.created_at,
          actor: comment.user.login,
          text: truncate_text(comment.body, 50),
          event: "commented"
        }
      end

      # Get events (labels, assignments, deployments)
      events = @client.issue_events("#{@owner}/#{@repo}", pr_number, per_page: 20)
      events.each do |event|
        next unless event.created_at # Skip events without timestamps

        text = case event.event
        when "labeled"
          "added label: #{event.label&.name}"
        when "unlabeled"
          "removed label: #{event.label&.name}"
        when "assigned"
          "assigned @#{event.assignee&.login}"
        when "closed"
          "closed PR"
        when "reopened"
          "reopened PR"
        when "deployed"
          "deployed"
        when "review_requested"
          "requested review"
        else
          event.event.to_s.gsub("_", " ")
        end

        activities << {
          type: "event",
          time: event.created_at,
          actor: event.actor&.login || "system",
          text: text,
          event: event.event
        }
      end

      # Get recent commits (last 5)
      commits = @client.pull_request_commits("#{@owner}/#{@repo}", pr_number, per_page: 5)
      commits.last(5).each do |commit|
        activities << {
          type: "commit",
          time: commit.commit.author.date,
          actor: commit.author&.login || commit.commit.author.name,
          text: truncate_text(commit.commit.message, 40),
          event: "committed"
        }
      end

      # Sort by time and get most recent
      sorted = activities.sort_by { |a| a[:time] }.reverse.first(limit)

      # Format for display
      sorted.map do |activity|
        time_ago = time_ago_in_words(activity[:time])
        "@#{activity[:actor]} #{activity[:text]} (#{time_ago})"
      end
    rescue => e
      Rails.logger.error "Error fetching timeline for PR ##{pr_number}: #{e.message}"
      [ "Error loading timeline" ]
    end
  end

  private

  def truncate_text(text, max_length)
    return "" if text.nil?
    text = text.split("\n").first || ""
    text.length > max_length ? "#{text[0...max_length]}..." : text
  end

  def time_ago_in_words(time)
    return "unknown" unless time

    seconds = Time.now - time
    case seconds
    when 0...60
      "just now"
    when 60...3600
      "#{(seconds / 60).round}m ago"
    when 3600...86400
      "#{(seconds / 3600).round}h ago"
    when 86400...604800
      "#{(seconds / 86400).round}d ago"
    else
      time.strftime("%b %d")
    end
  end
end
