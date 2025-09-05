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
  
  # Check if group already exists (idempotent operation)
  group = case Repo.get_by(Groups.Group, name: config.name) do
    nil ->
      {:ok, group} = Groups.create_group_with_creator(%{
        "name" => config.name,
        "description" => config.description,
        "visibility" => config.visibility,
        "join_policy" => config.join_policy
      }, creator)
      Logger.info("Created new group: #{group.name}")
      group
    existing_group ->
      Logger.info("Group already exists: #{existing_group.name}")
      existing_group
  end
  
  # Add 2-5 additional members to each group (excluding creator to avoid re-addition)
  target_member_count = Enum.random(2..5)
  
  successful_additions = users
  |> Enum.reject(&(&1.id == creator.id))  # Remove creator from potential members
  |> Enum.take_random(target_member_count)
  |> Enum.map(fn user ->
    role = Enum.random(["member", "admin"])
    # Pass the creator as acting_user so they can add members even to private groups
    case Groups.add_user_to_group(group, user, role, creator) do
      {:ok, _} -> 1
      {:error, :already_member} -> 0
      {:error, _} -> 0
    end
  end)
  |> Enum.sum()
  
  # Total members = creator (1) + successful additions
  total_members = 1 + successful_additions
  Logger.info("Group #{group.name} now has #{total_members} members (#{successful_additions} added)")
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