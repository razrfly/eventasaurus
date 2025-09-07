# Audit RCV polls and their events to understand why they're not showing in the dashboard

import Ecto.Query
alias EventasaurusApp.{Repo, Events}

# Safe helper functions to avoid nil crashes
fmt_dt = fn
  nil -> "n/a"
  dt -> Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end

safe_slice = fn
  nil, _n -> ""
  s, n -> String.slice(s, 0, n)
end

IO.puts("=== RCV POLL AUDIT ===")

# Get all RCV polls with their events
rcv_polls_query = from(p in Events.Poll,
  join: e in Events.Event, on: p.event_id == e.id,
  left_join: po in Events.PollOption, on: po.poll_id == p.id,
  where: p.voting_system == "ranked" and is_nil(p.deleted_at) and is_nil(e.deleted_at),
  select: {p, e, count(po.id)},
  group_by: [p.id, e.id],
  order_by: [desc: e.start_at]
)

rcv_polls = Repo.all(rcv_polls_query)

IO.puts("Found #{length(rcv_polls)} RCV polls:")
IO.puts("")

Enum.each(rcv_polls, fn {poll, event, option_count} ->
  IO.puts("📊 Poll: #{poll.title}")
  IO.puts("   Event: #{event.title}")
  IO.puts("   Event Date: #{fmt_dt.(event.start_at)}")
  IO.puts("   Poll Phase: #{poll.phase}")
  IO.puts("   Poll Type: #{poll.poll_type}")
  IO.puts("   Options: #{option_count}")
  IO.puts("   Event Status: #{event.status}")
  IO.puts("   Event Visibility: #{event.visibility}")
  IO.puts("   Event Deleted?: #{if event.deleted_at, do: "YES", else: "NO"}")
  IO.puts("   Poll Deleted?: #{if poll.deleted_at, do: "YES", else: "NO"}")
  IO.puts("")
end)

# Check specifically for movie events
IO.puts("=== MOVIE EVENTS WITH POLLS ===")

movie_events_query = from(e in Events.Event,
  left_join: p in Events.Poll, on: p.event_id == e.id and is_nil(p.deleted_at),
  where: ilike(e.title, "%movie%") and is_nil(e.deleted_at),
  select: {e, count(p.id)},
  group_by: e.id,
  order_by: [desc: e.start_at]
)

movie_events = Repo.all(movie_events_query)

IO.puts("Found #{length(movie_events)} movie events:")
IO.puts("")

Enum.each(movie_events, fn {event, poll_count} ->
  IO.puts("🎬 Event: #{event.title}")
  IO.puts("   Date: #{fmt_dt.(event.start_at)}")
  IO.puts("   Status: #{event.status}")
  IO.puts("   Poll Count: #{poll_count}")
  IO.puts("   Visibility: #{event.visibility}")
  if poll_count == 0 do
    IO.puts("   ⚠️  NO POLLS FOUND FOR THIS MOVIE EVENT")
  end
  IO.puts("")
end)

# Check events that should have RCV polls but don't
IO.puts("=== EVENTS WITH DESCRIPTION MENTIONING RCV ===")

rcv_description_events = from(e in Events.Event,
  left_join: p in Events.Poll, on: p.event_id == e.id and is_nil(p.deleted_at),
  where: (ilike(e.description, "%ranked choice%") or ilike(e.description, "%rcv%")) and is_nil(e.deleted_at),
  select: {e, count(p.id)},
  group_by: e.id,
  order_by: [desc: e.start_at]
) |> Repo.all()

IO.puts("Found #{length(rcv_description_events)} events mentioning RCV in description:")
IO.puts("")

Enum.each(rcv_description_events, fn {event, poll_count} ->
  IO.puts("📋 Event: #{event.title}")
  IO.puts("   Date: #{fmt_dt.(event.start_at)}")
  IO.puts("   Status: #{event.status}")
  IO.puts("   Poll Count: #{poll_count}")
  IO.puts("   Description: #{safe_slice.(event.description, 100)}...")
  if poll_count == 0 do
    IO.puts("   ❌ NO POLLS DESPITE MENTIONING RCV")
  else
    # Check if any are RCV polls
    rcv_polls_for_event = from(p in Events.Poll,
      where: p.event_id == ^event.id and p.voting_system == "ranked" and is_nil(p.deleted_at),
      select: count(p.id)
    ) |> Repo.one()
    
    if rcv_polls_for_event > 0 do
      IO.puts("   ✅ Has #{rcv_polls_for_event} RCV polls")
    else
      IO.puts("   ⚠️  Has polls but NONE are RCV")
    end
  end
  IO.puts("")
end)