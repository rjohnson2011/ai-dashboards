class AddLastScrapedAtToPullRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :pull_requests, :last_scraped_at, :datetime
  end
end
