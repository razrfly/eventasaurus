import Ecto.Query

alias EventasaurusApp.Events
alias EventasaurusApp.Repo

# Get current data counts
events_count = Repo.aggregate(Events.Event, :count, :id)
IO.puts("Total Events: #{events_count}")

polls_count = from(p in Events.Poll, where: is_nil(p.deleted_at)) |> Repo.aggregate(:count, :id)
IO.puts("Total Active Polls: #{polls_count}")

# Get polls by type and voting system
polls_by_type =
  from(p in Events.Poll,
    where: is_nil(p.deleted_at),
    group_by: [p.poll_type, p.voting_system],
    select: {p.poll_type, p.voting_system, count(p.id)}
  )
  |> Repo.all()

IO.puts("Polls by Type and Voting System:")
Enum.each(polls_by_type, fn {type, system, count} -> IO.puts("  #{type}/#{system}: #{count}") end)

# Get poll options count
options_count =
  from(o in Events.PollOption, where: is_nil(o.deleted_at)) |> Repo.aggregate(:count, :id)

IO.puts("Total Poll Options: #{options_count}")

# Get votes by type
votes_by_type =
  from(v in Events.PollVote, group_by: v.vote_value, select: {v.vote_value, count(v.id)})
  |> Repo.all()

IO.puts("Votes by Type:")
Enum.each(votes_by_type, fn {type, count} -> IO.puts("  #{type}: #{count}") end)

# Get unique participants - optimized for database
participants =
  from(v in Events.PollVote, select: count(fragment("DISTINCT (?)", v.voter_id))) |> Repo.one()

IO.puts("Unique Poll Participants: #{participants}")

# Check for RCV specifically - fix voting system name from "rcv" to "ranked"
rcv_polls =
  from(p in Events.Poll, where: is_nil(p.deleted_at) and p.voting_system == "ranked")
  |> Repo.aggregate(:count, :id)

IO.puts("RCV Polls: #{rcv_polls}")

# Check movie polls specifically
movie_polls =
  from(p in Events.Poll, where: is_nil(p.deleted_at) and p.poll_type == "movie")
  |> Repo.aggregate(:count, :id)

IO.puts("Movie Polls: #{movie_polls}")
