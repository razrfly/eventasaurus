import Ecto.Query
alias EventasaurusApp.{Repo, Events, Accounts}

# Get movie_buff user
movie_buff = Repo.get_by(Accounts.User, email: "movie_buff@example.com")

if movie_buff do
  IO.puts("=== MOVIE_BUFF@EXAMPLE.COM EVENT AUDIT ===")
  
  # Get movie_buff events
  events = from(e in Events.Event,
    join: eu in "event_users", on: eu.event_id == e.id,
    where: eu.user_id == ^movie_buff.id and is_nil(e.deleted_at),
    order_by: [desc: e.start_at]
  ) |> Repo.all()
  
  IO.puts("Found #{length(events)} events for movie_buff@example.com:")
  IO.puts("")
  
  movie_events_with_rcv = 0
  total_movie_events = 0
  
  Enum.each(events, fn event ->
    # Get polls for this event
    polls = from(p in Events.Poll, 
      where: p.event_id == ^event.id and is_nil(p.deleted_at)
    ) |> Repo.all()
    
    rcv_polls = polls |> Enum.filter(&(&1.voting_system == "ranked"))
    
    is_movie = String.contains?(String.downcase(event.title), "movie")
    if is_movie, do: total_movie_events = total_movie_events + 1
    if is_movie and length(rcv_polls) > 0, do: movie_events_with_rcv = movie_events_with_rcv + 1
    
    IO.puts("📽️ #{event.title}")
    IO.puts("   Date: #{Calendar.strftime(event.start_at, "%Y-%m-%d %H:%M")}")
    IO.puts("   Status: #{event.status}")
    IO.puts("   Total Polls: #{length(polls)}")
    IO.puts("   RCV Polls: #{length(rcv_polls)}")
    
    if is_movie and length(rcv_polls) == 0 do
      IO.puts("   ❌ MOVIE EVENT WITHOUT RCV POLL!")
    elsif is_movie and length(rcv_polls) > 0 do
      IO.puts("   ✅ Movie event has RCV poll(s)")
    end
    IO.puts("")
  end)
  
  IO.puts("=== SUMMARY ===")
  IO.puts("Total movie_buff events: #{length(events)}")
  IO.puts("Movie events: #{total_movie_events}")
  IO.puts("Movie events with RCV polls: #{movie_events_with_rcv}")
  if total_movie_events > 0 do
    IO.puts("Success rate: #{round(movie_events_with_rcv/total_movie_events*100)}%")
  end
else
  IO.puts("❌ movie_buff@example.com user not found!")
end
