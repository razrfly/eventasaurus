#!/usr/bin/env elixir

# Script to manually retry a failed Oban job to test telemetry hook
job = EventasaurusApp.Repo.get!(Oban.Job, 221)
IO.puts("Retrying job #{job.id}...")
Oban.retry_job(job)
IO.puts("Job retry initiated!")
