class FetchBackendReviewGroupService
  TEAM_URL = "https://api.github.com/orgs/department-of-veterans-affairs/teams/backend-review-group/members"

  def self.call
    new.call
  end

  def call
    response = fetch_team_members

    if response.success?
      members = response.parsed_response.map do |member|
        {
          username: member["login"],
          avatar_url: member["avatar_url"]
        }
      end

      BackendReviewGroupMember.refresh_members(members)
      Rails.logger.info "Successfully fetched #{members.size} backend review group members"
      { success: true, count: members.size }
    else
      Rails.logger.error "Failed to fetch backend review group members: #{response.code} - #{response.message}"
      { success: false, error: response.message }
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching backend review group members: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def fetch_team_members
    HTTParty.get(
      TEAM_URL,
      headers: {
        "Authorization" => "token #{ENV['GITHUB_ACCESS_TOKEN']}",
        "Accept" => "application/vnd.github.v3+json"
      }
    )
  end
end
