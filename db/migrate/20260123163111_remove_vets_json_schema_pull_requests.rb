class RemoveVetsJsonSchemaPullRequests < ActiveRecord::Migration[8.0]
  def up
    # Remove vets-json-schema PRs from dashboard (can be re-enabled later)
    # Must delete associated records first due to foreign key constraints

    # Delete check_runs for vets-json-schema PRs
    execute <<-SQL
      DELETE FROM check_runs
      WHERE pull_request_id IN (
        SELECT id FROM pull_requests WHERE repository_name = 'vets-json-schema'
      )
    SQL

    # Delete pull_request_reviews for vets-json-schema PRs
    execute <<-SQL
      DELETE FROM pull_request_reviews
      WHERE pull_request_id IN (
        SELECT id FROM pull_requests WHERE repository_name = 'vets-json-schema'
      )
    SQL

    # Delete pull_request_comments for vets-json-schema PRs
    execute <<-SQL
      DELETE FROM pull_request_comments
      WHERE pull_request_id IN (
        SELECT id FROM pull_requests WHERE repository_name = 'vets-json-schema'
      )
    SQL

    # Now delete the PRs themselves
    execute <<-SQL
      DELETE FROM pull_requests WHERE repository_name = 'vets-json-schema'
    SQL
  end

  def down
    # PRs would need to be re-scraped to restore
    # No-op for rollback
  end
end
