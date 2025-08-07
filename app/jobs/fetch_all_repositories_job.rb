class FetchAllRepositoriesJob < ApplicationJob
  queue_as :default
  
  def perform
    Rails.logger.info "[FetchAllRepositoriesJob] Starting update for all configured repositories"
    
    RepositoryConfig.all.each do |repo_config|
      Rails.logger.info "[FetchAllRepositoriesJob] Queuing update for #{repo_config.full_name}"
      
      FetchAllPullRequestsJob.perform_later(
        repository_name: repo_config.name,
        repository_owner: repo_config.owner
      )
    end
    
    Rails.logger.info "[FetchAllRepositoriesJob] Queued updates for #{RepositoryConfig.all.count} repositories"
  end
end