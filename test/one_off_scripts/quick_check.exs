import Ecto.Query

alias EventasaurusApp.Events
alias EventasaurusApp.Repo

# Get current poll counts by voting system
polls =
  from(p in Events.Poll,
    where: is_nil(p.deleted_at),
    group_by: p.voting_system,
    select: {p.voting_system, count(p.id)}
  )
  |> Repo.all()

IO.puts("=== CURRENT POLL COUNTS BY VOTING SYSTEM ===")

Enum.each(polls, fn {system, count} ->
  IO.puts("#{system}: #{count}")
end)

# Check for RCV specifically
rcv_polls =
  from(p in Events.Poll, where: is_nil(p.deleted_at) and p.voting_system == "ranked")
  |> Repo.aggregate(:count)

IO.puts("\n*** RCV/Ranked Polls: #{rcv_polls} ***")
