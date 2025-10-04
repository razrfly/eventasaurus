import Ecto.Query

alias EventasaurusApp.Events
alias EventasaurusApp.Repo

# Get detailed poll information
polls =
  from(p in Events.Poll, where: is_nil(p.deleted_at), preload: [:poll_options]) |> Repo.all()

IO.puts("=== CURRENT POLL AUDIT ===")
IO.puts("Total Polls: #{length(polls)}")

Enum.with_index(polls, 1)
|> Enum.each(fn {poll, index} ->
  IO.puts("\n#{index}. Poll ID: #{poll.id}")
  IO.puts("   Title: #{poll.title}")
  IO.puts("   Type: #{poll.poll_type}")
  IO.puts("   Voting System: #{poll.voting_system}")
  IO.puts("   Phase: #{poll.phase}")
  IO.puts("   Options: #{length(poll.poll_options)}")

  if poll.voting_system == "ranked" do
    IO.puts("   *** THIS IS AN RCV POLL ***")
  end
end)

# Check seeds that should be running
IO.puts("\n=== CHECKING POLL CREATION ===")

if File.exists?("priv/repo/dev_seeds/poll_seed.exs") do
  IO.puts("poll_seed.exs exists - should create RCV polls")
else
  IO.puts("poll_seed.exs missing")
end
