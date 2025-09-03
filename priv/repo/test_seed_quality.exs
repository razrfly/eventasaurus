# Test script to verify seed data quality
alias EventasaurusApp.{Repo, Events, Accounts}
alias EventasaurusApp.Events.{Event, Poll}
import Ecto.Query

IO.puts("\n=== SEED DATA QUALITY CHECK ===\n")

# Check for Lorem ipsum in events
lorem_events = Repo.aggregate(
  from(e in Event, where: ilike(e.title, "%lorem%") or ilike(e.title, "%corrupti%")),
  :count
)
total_events = Repo.aggregate(Event, :count)

IO.puts("Events with Lorem ipsum: #{lorem_events}/#{total_events}")

# Check movie_buff events
movie_buff = Accounts.get_user_by_email("movie_buff@example.com")
if movie_buff do
  movie_events = Repo.all(
    from e in Event,
    join: eu in EventasaurusApp.Events.EventUser,
    on: eu.event_id == e.id,
    where: eu.user_id == ^movie_buff.id and eu.role in ["owner", "organizer"] and ilike(e.title, "%movie%"),
    select: e.title
  )
  IO.puts("\nmovie_buff's movie events (#{length(movie_events)}):")
  Enum.each(movie_events, fn title -> IO.puts("  - #{title}") end)
end

# Check foodie events
foodie = Accounts.get_user_by_email("foodie_friend@example.com")
if foodie do
  food_events = Repo.all(
    from e in Event,
    join: eu in EventasaurusApp.Events.EventUser,
    on: eu.event_id == e.id,
    where: eu.user_id == ^foodie.id and eu.role in ["owner", "organizer"] and 
           (ilike(e.title, "%dinner%") or ilike(e.title, "%restaurant%")),
    select: e.title
  )
  IO.puts("\nfoodie_friend's restaurant events (#{length(food_events)}):")
  Enum.each(food_events, fn title -> IO.puts("  - #{title}") end)
end

# Check polls with movie options
movie_polls = Repo.all(
  from p in Poll,
  where: p.poll_type == "movie" and p.voting_system == "ranked",
  preload: :options
)

IO.puts("\nMovie RCV polls (#{length(movie_polls)}):")
Enum.each(movie_polls, fn poll ->
  IO.puts("  Poll: #{poll.title}")
  Enum.each(poll.options, fn option ->
    IO.puts("    - #{option.title}")
  end)
end)

# Sample recent events
recent_events = Repo.all(
  from e in Event,
  order_by: [desc: e.inserted_at],
  limit: 10,
  select: {e.title, e.status}
)

IO.puts("\nRecent events:")
Enum.each(recent_events, fn {title, status} ->
  IO.puts("  - [#{status}] #{title}")
end)

IO.puts("\n=== CHECK COMPLETE ===\n")