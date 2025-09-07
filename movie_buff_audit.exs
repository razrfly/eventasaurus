import Ecto.Query
alias EventasaurusApp.{Repo, Events, Accounts}

# Get movie_buff user
movie_buff = Repo.get_by(Accounts.User, email: "movie_buff@example.com")

if movie_buff do
  IO.puts("=== MOVIE_BUFF@EXAMPLE.COM EVENT AUDIT ===")
  
  # Get movie_buff events with their polls
  events_query = from(e in Events.Event,
    left_join: eu in "event_users", on: eu.event_id == e.id,
    left_join: p in Events.Poll, on: p.event_id == e.id and is_nil(p.deleted_at),
    where: eu.user_id == ^movie_buff.id and is_nil(e.deleted_at),
    select: {e, count(p.id), fragment("array_agg(? ORDER BY ?) FILTER (WHERE ? IS NOT NULL)", p.voting_system, p.id, p.id)},
    group_by: e.id,
    order_by: [desc: e.start_at]
  )
  
  events = Repo.all(events_query)
  
  IO.puts("Found #{length(events)} events for movie_buff@example.com:")
  IO.puts("")
  
  Enum.each(events, fn {event, poll_count, voting_systems} ->
    rcv_count = if voting_systems && voting_systems != [nil] do
      voting_systems |> Enum.count(&(&1 == "ranked"))
    else
      0
    end
    
    IO.puts("📽️ #{event.title}")
    IO.puts("   Date: #{Calendar.strftime(event.start_at, "%Y-%m-%d %H:%M")}")
    IO.puts("   Status: #{event.status}")
    IO.puts("   Total Polls: #{poll_count}")
    IO.puts("   RCV Polls: #{rcv_count}")
    IO.puts("   Voting Systems: #{inspect(voting_systems)}")
    
    if String.contains?(String.downcase(event.title), "movie") and rcv_count == 0 do
      IO.puts("   ❌ MOVIE EVENT WITHOUT RCV POLL!")
    elsif String.contains?(String.downcase(event.title), "movie") and rcv_count > 0 do
      IO.puts("   ✅ Movie event has RCV poll(s)")
    end
    IO.puts("")
  end)
  
  # Summary
  total_movie_events = events |> Enum.filter(fn {event, _, _} -> 
    String.contains?(String.downcase(event.title), "movie") 
  end) |> length()
  
  movie_events_with_rcv = events |> Enum.filter(fn {event, _, voting_systems} -> 
    String.contains?(String.downcase(event.title), "movie") and 
    voting_systems && Enum.any?(voting_systems, &(&1 == "ranked"))
  end) |> length()
  
  IO.puts("=== SUMMARY ===")
  IO.puts("Total movie_buff events: #{length(events)}")
  IO.puts("Movie events: #{total_movie_events}")
  IO.puts("Movie events with RCV polls: #{movie_events_with_rcv}")
  IO.puts("Success rate: #{if total_movie_events > 0, do: round(movie_events_with_rcv/total_movie_events*100), else: 0}%")
else
  IO.puts("❌ movie_buff@example.com user not found!")
end
