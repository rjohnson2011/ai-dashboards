class RepositoryConfig
  include ActiveModel::Model
  
  attr_accessor :owner, :name, :display_name, :backend_review_required
  
  def self.all
    @all ||= load_repositories
  end
  
  def self.find_by_name(repo_name)
    all.find { |repo| repo.name == repo_name }
  end
  
  def self.load_repositories
    config = YAML.load_file(Rails.root.join('config', 'repositories.yml'))
    config['repositories'].map do |repo_data|
      new(
        owner: repo_data['owner'],
        name: repo_data['name'],
        display_name: repo_data['display_name'],
        backend_review_required: repo_data['backend_review_required'] || false
      )
    end
  end
  
  def full_name
    "#{owner}/#{name}"
  end
  
  def backend_review_required?
    backend_review_required
  end
end