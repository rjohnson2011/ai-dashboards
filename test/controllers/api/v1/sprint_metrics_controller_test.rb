require "test_helper"

class Api::V1::SprintMetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ReviewEvent.delete_all
    BackendReviewGroupMember.delete_all
    Rails.cache.clear
    @token = SessionTokenService.issue_with_prefix(email: "tester@va.gov", name: "Tester")
  end

  def approve(github_id:, reviewer:, ago:, pr_author: "alice")
    ReviewEvent.create!(
      github_id: github_id, reviewer: reviewer, state: "APPROVED", submitted_at: ago.ago,
      pr_author: pr_author, repository_name: "vets-api", repository_owner: "dsva", pr_number: github_id
    )
  end

  test "reviewer_activity includes the last 90 days of approvals as events" do
    approve(github_id: 1, reviewer: "bob", ago: 2.days)
    approve(github_id: 2, reviewer: "carol", ago: 1.day, pr_author: "dependabot")
    approve(github_id: 3, reviewer: "bob", ago: 120.days)

    get "/api/v1/reviews/reviewer_activity", headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[bob carol], body["events"].map { |e| e["reviewer"] }
    assert_equal [ false, true ], body["events"].map { |e| e["dependabot"] }
    assert body["events"].first.key?("at")
    # The per-window totals are untouched.
    assert_equal [ { "reviewer" => "bob", "count" => 1 }, { "reviewer" => "carol", "count" => 1 } ],
                 body["scopes"]["all"]["week"].sort_by { |r| r["reviewer"] }
  end

  test "reviewer_activity events honor the backend_only filter" do
    BackendReviewGroupMember.create!(username: "carol")
    approve(github_id: 1, reviewer: "bob", ago: 2.days)
    approve(github_id: 2, reviewer: "carol", ago: 1.day)

    get "/api/v1/reviews/reviewer_activity", params: { backend_only: "true" },
        headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    assert_equal [ "carol" ], JSON.parse(response.body)["events"].map { |e| e["reviewer"] }
  end

  test "events_days widens the events window, capped at a year" do
    approve(github_id: 1, reviewer: "bob", ago: 120.days)
    approve(github_id: 2, reviewer: "carol", ago: 400.days)

    get "/api/v1/reviews/reviewer_activity", params: { events_days: "1000" },
        headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    assert_equal [ "bob" ], JSON.parse(response.body)["events"].map { |e| e["reviewer"] }
  end
end
