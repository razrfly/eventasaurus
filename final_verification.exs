import Ecto.Query
alias EventasaurusApp.{Repo, Events, Accounts}

# Simple verification query
movie_buff = Repo.get_by(Accounts.User, email: "movie_buff@example.com")

if movie_buff do
  IO.puts("✅ movie_buff@example.com user exists (ID: #{movie_buff.id})")
  
  # Count movie_buff events with RCV polls
  rcv_movie_count = from(e in Events.Event,
    join: eu in "event_users", on: eu.event_id == e.id,
    join: p in Events.Poll, on: p.event_id == e.id,
    where: eu.user_id == ^movie_buff.id and is_nil(e.deleted_at) and is_nil(p.deleted_at) 
      and p.voting_system == "ranked" and ilike(e.title, "%movie%")
  ) |> Repo.aggregate(:count, :id)
  
  IO.puts("✅ movie_buff movie events with RCV polls: #{rcv_movie_count}")
  
  # Total RCV polls in system
  total_rcv = from(p in Events.Poll,
    where: is_nil(p.deleted_at) and p.voting_system == "ranked"
  ) |> Repo.aggregate(:count, :id)
  
  IO.puts("✅ Total RCV polls in system: #{total_rcv}")
else
  IO.puts("❌ movie_buff@example.com user not found!")
end
