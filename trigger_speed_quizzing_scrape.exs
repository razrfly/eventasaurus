#!/usr/bin/env elixir

# Trigger Speed Quizzing scrape with new time extraction code

alias EventasaurusDiscovery.Sources.SpeedQuizzing
alias Eventasaurus.Repo

IO.puts("=" |> String.duplicate(100))
IO.puts("🔄 TRIGGERING SPEED QUIZZING RE-SCRAPE")
IO.puts("=" |> String.duplicate(100))
IO.puts("")

# Enqueue Speed Quizzing sync job with force=true to bypass freshness checks
job_args = %{
  "force" => true,
  "limit" => nil  # Get all events
}

IO.puts("📋 Enqueueing Speed Quizzing sync job with force=true...")

case SpeedQuizzing.Jobs.SyncJob.new(job_args) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Speed Quizzing sync job enqueued successfully!")
    IO.puts("   Job ID: #{job.id}")
    IO.puts("   Queue: #{job.queue}")
    IO.puts("   State: #{job.state}")
    IO.puts("")
    IO.puts("⏳ Waiting for job to complete...")
    IO.puts("   This may take 1-2 minutes as it fetches and processes all events")
    IO.puts("")
    IO.puts("💡 Run 'mix run verify_time_quality.exs' after a few minutes to check results")

  {:error, reason} ->
    IO.puts("❌ Failed to enqueue job: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("")
IO.puts("=" |> String.duplicate(100))
