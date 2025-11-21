#!/usr/bin/env ruby
# Script to populate backend team members and update PR approvals

require 'logger'

logger = Logger.new(STDOUT)
logger.info "Populating backend team members..."

# Define the backend team members
BACKEND_TEAM_MEMBERS = [
  { username: 'ericboehs' },
  { username: 'LindseySaari' },
  { username: 'rmtolmach' },
  { username: 'stiehlrod' },
  { username: 'RachalCassity' },
  { username: 'rjohnson2011' },
  { username: 'stevenjcumming' }
]

# Check current members
logger.info "Current backend team members in database:"
BackendReviewGroupMember.all.each do |member|
  logger.info "  - #{member.username}"
end

# Populate or update the backend team
logger.info "\nUpdating backend team members..."
BackendReviewGroupMember.transaction do
  BACKEND_TEAM_MEMBERS.each do |member_data|
    member = BackendReviewGroupMember.find_or_initialize_by(username: member_data[:username])
    if member.new_record?
      member.save!
      logger.info "  Added: #{member.username}"
    else
      logger.info "  Already exists: #{member.username}"
    end
  end
end

# Remove any members not in the list
removed_members = BackendReviewGroupMember.where.not(username: BACKEND_TEAM_MEMBERS.map { |m| m[:username] })
if removed_members.any?
  logger.info "\nRemoving members no longer in the team:"
  removed_members.each do |member|
    logger.info "  - #{member.username}"
    member.destroy
  end
end

logger.info "\nUpdated backend team has #{BackendReviewGroupMember.count} members"

# Now update all open PR backend approval statuses
logger.info "\nUpdating backend approval status for all open PRs..."
updated_count = 0
changed_count = 0

PullRequest.open.includes(:pull_request_reviews).find_each do |pr|
  old_status = pr.backend_approval_status
  pr.update_backend_approval_status!
  pr.reload
  updated_count += 1

  if old_status != pr.backend_approval_status
    changed_count += 1
    logger.info "  PR ##{pr.number}: #{old_status} -> #{pr.backend_approval_status}"
  end
end

logger.info "\nCompleted!"
logger.info "  Total PRs updated: #{updated_count}"
logger.info "  PRs with status changes: #{changed_count}"

# Check specific PRs that were problematic
problem_prs = [ 23835, 23857, 23845 ]
logger.info "\nChecking problematic PRs:"
PullRequest.where(number: problem_prs).each do |pr|
  logger.info "  PR ##{pr.number}:"
  logger.info "    Backend approval status: #{pr.backend_approval_status}"
  logger.info "    Approved by: #{pr.approval_summary[:approved_users].inspect if pr.approval_summary}"
end
