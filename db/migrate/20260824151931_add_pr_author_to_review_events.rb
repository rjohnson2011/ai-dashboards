class AddPrAuthorToReviewEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :review_events, :pr_author, :string
  end
end
