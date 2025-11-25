class Api::V1::AdminController < ApplicationController
  before_action :authenticate_admin

  def run_task
    task_name = params[:task]
    task_args = params[:args] || []

    begin
      # Run the rake task
      Rake::Task[task_name].invoke(*task_args)
      
      render json: { success: true, message: "Task #{task_name} completed successfully" }
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def authenticate_admin
    token = request.headers['Authorization']&.gsub(/^Bearer /, '')
    
    unless token == ENV['ADMIN_TOKEN']
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end
