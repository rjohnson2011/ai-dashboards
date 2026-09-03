require "test_helper"

class ReviewEventTest < ActiveSupport::TestCase
  setup do
    ReviewEvent.delete_all
    @now = Time.zone.parse("2026-09-02 12:00:00")
  end

  def record(github_id:, reviewer:, submitted_at:, state: "APPROVED", pr_author: "alice", repository_name: "vets-api")
    ReviewEvent.create!(
      github_id: github_id, reviewer: reviewer, state: state, submitted_at: submitted_at,
      pr_author: pr_author, repository_name: repository_name, repository_owner: "dsva", pr_number: github_id
    )
  end

  test "recent_approvals returns approvals since the cutoff, oldest first, flagged for dependabot" do
    record(github_id: 1, reviewer: "bob", submitted_at: @now - 2.days)
    record(github_id: 2, reviewer: "carol", submitted_at: @now - 1.day, pr_author: "dependabot[bot]")
    record(github_id: 3, reviewer: "bob", submitted_at: @now - 10.days) # before cutoff
    record(github_id: 4, reviewer: "dan", submitted_at: @now - 1.hour, state: "COMMENTED") # not counted

    events = ReviewEvent.recent_approvals(@now - 7.days)

    assert_equal [
      { reviewer: "bob", at: (@now - 2.days).iso8601, dependabot: false, pr: 1, repo: "vets-api",
        title: nil, url: "https://va.ghe.com/dsva/vets-api/pull/1" },
      { reviewer: "carol", at: (@now - 1.day).iso8601, dependabot: true, pr: 2, repo: "vets-api",
        title: nil, url: "https://va.ghe.com/dsva/vets-api/pull/2" }
    ], events
  end

  test "recent_approvals narrows to the given reviewers" do
    record(github_id: 1, reviewer: "bob", submitted_at: @now - 2.days)
    record(github_id: 2, reviewer: "carol", submitted_at: @now - 1.day)

    events = ReviewEvent.recent_approvals(@now - 7.days, reviewers: [ "carol" ])

    assert_equal [ "carol" ], events.map { |e| e[:reviewer] }
  end
end
