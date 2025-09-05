# Create groups with diverse privacy settings for testing
alias EventasaurusApp.{Repo, Groups, Accounts}
import Ecto.Query
require Logger

Logger.info("Creating diverse privacy test groups...")

# Get users to create groups
users = Repo.all(from u in Accounts.User, limit: 10)

if length(users) < 3 do
  Logger.error("Not enough users! Need at least 3 users.")
  exit(:no_users)
end

# Define diverse group configs with specific privacy settings
diverse_group_configs = [
  # Private + Request groups
  %{name: "Private Book Club", description: "Exclusive literary discussions", visibility: "private", join_policy: "request"},
  %{name: "Inner Circle VIP", description: "Private community for VIPs", visibility: "private", join_policy: "request"},
  %{name: "Secret Society", description: "Invitation-only exclusive group", visibility: "private", join_policy: "invite_only"},
  
  # Unlisted groups
  %{name: "Underground Music", description: "Hidden music community", visibility: "unlisted", join_policy: "open"},
  %{name: "Speakeasy Social", description: "Unlisted social gatherings", visibility: "unlisted", join_policy: "request"},
  %{name: "Stealth Gaming", description: "Secret gaming sessions", visibility: "unlisted", join_policy: "invite_only"},
  
  # Public with restrictions
  %{name: "Elite Fitness Club", description: "Public but requires approval", visibility: "public", join_policy: "request"},
  %{name: "Professional Network", description: "Curated professional group", visibility: "public", join_policy: "request"},
  %{name: "Exclusive Foodies", description: "Invitation-only food community", visibility: "public", join_policy: "invite_only"}
]

created_groups = Enum.map(diverse_group_configs, fn config ->
  creator = Enum.random(users)
  
  Logger.info("Creating group: #{config.name} (#{config.visibility}/#{config.join_policy})")
  
  {:ok, group} = Groups.create_group_with_creator(%{
    "name" => config.name,
    "description" => config.description,
    "visibility" => config.visibility,
    "join_policy" => config.join_policy
  }, creator)
  
  # Add 2-5 members to each group
  member_count = Enum.random(2..5)
  
  users
  |> Enum.take_random(member_count)
  |> Enum.each(fn user ->
    role = if user.id == creator.id, do: "owner", else: Enum.random(["member", "admin"])
    Groups.add_user_to_group(group, user, role)
  end)
  
  Logger.info("Created group: #{group.name} with #{member_count} members")
  group
end)

Logger.info("Created #{length(created_groups)} diverse privacy groups!")
Logger.info("Summary:")
Logger.info("- Private + Request: 2 groups")  
Logger.info("- Private + Invite Only: 1 group")
Logger.info("- Unlisted + Open: 1 group")
Logger.info("- Unlisted + Request: 1 group") 
Logger.info("- Unlisted + Invite Only: 1 group")
Logger.info("- Public + Request: 2 groups")
Logger.info("- Public + Invite Only: 1 group")