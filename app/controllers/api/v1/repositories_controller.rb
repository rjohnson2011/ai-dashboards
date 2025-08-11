class Api::V1::RepositoriesController < ApplicationController
  def index
    repositories = RepositoryConfig.all.map do |repo|
      {
        owner: repo.owner,
        name: repo.name,
        display_name: repo.display_name,
        full_name: repo.full_name,
        backend_review_required: repo.backend_review_required?
      }
    end

    render json: { repositories: repositories }
  end
end
