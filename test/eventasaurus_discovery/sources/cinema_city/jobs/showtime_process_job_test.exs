defmodule EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJobTest do
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob

  describe "perform/1 - movie dependency handling" do
    test "returns {:snooze, 30} when movie is not ready yet" do
      # Create a job with a film that doesn't exist in the database
      # and no MovieDetailJob has been created for it
      job_args = %{
        "showtime" => %{
          "film" => %{
            "cinema_city_film_id" => "nonexistent_film_12345",
            "polish_title" => "Test Movie"
          },
          "event" => %{
            "cinema_city_event_id" => "event_123",
            "showtime" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "auditorium" => "Sala 1",
            "booking_url" => "https://example.com/book"
          },
          "cinema_data" => %{
            "name" => "Test Cinema",
            "cinema_city_id" => "cinema_123"
          },
          "external_id" => "cinema_city_showtime_cinema_123_nonexistent_film_12345_event_123"
        },
        "source_id" => nil,
        "cinema_city_event_id" => "event_123"
      }

      # Create a minimal Oban job struct
      job = %Oban.Job{
        id: 1,
        args: job_args,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob",
        queue: "scraper",
        state: "executing",
        attempt: 1,
        max_attempts: 5
      }

      # The job should snooze because:
      # 1. Movie doesn't exist in database
      # 2. No MovieDetailJob exists for this film_id
      result = ShowtimeProcessJob.perform(job)

      assert {:snooze, 30} = result
    end

    test "returns {:cancel, :movie_not_matched} when MovieDetailJob completed but movie not matched" do
      # First, create a completed MovieDetailJob that didn't create a movie
      # (simulating TMDB match failure)
      {:ok, movie_detail_job} =
        Oban.Job.new(
          %{
            "cinema_city_film_id" => "failed_match_film_999",
            "film_data" => %{"polish_title" => "Unmatchable Movie"},
            "source_id" => nil
          },
          worker: EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob,
          queue: :scraper_detail
        )
        |> Oban.insert()

      # Mark the job as discarded (simulating TMDB match failure)
      Repo.update_all(
        from(j in Oban.Job, where: j.id == ^movie_detail_job.id),
        set: [state: "discarded", discarded_at: DateTime.utc_now()]
      )

      # Now create a ShowtimeProcessJob for the same film
      job_args = %{
        "showtime" => %{
          "film" => %{
            "cinema_city_film_id" => "failed_match_film_999",
            "polish_title" => "Unmatchable Movie"
          },
          "event" => %{
            "cinema_city_event_id" => "event_456",
            "showtime" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "auditorium" => "Sala 2",
            "booking_url" => "https://example.com/book"
          },
          "cinema_data" => %{
            "name" => "Test Cinema",
            "cinema_city_id" => "cinema_123"
          },
          "external_id" => "cinema_city_showtime_cinema_123_failed_match_film_999_event_456"
        },
        "source_id" => nil,
        "cinema_city_event_id" => "event_456"
      }

      job = %Oban.Job{
        id: 2,
        args: job_args,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob",
        queue: "scraper",
        state: "executing",
        attempt: 1,
        max_attempts: 5
      }

      # Should cancel because MovieDetailJob is discarded (no movie will ever be created)
      result = ShowtimeProcessJob.perform(job)

      assert {:cancel, :movie_not_matched} = result
    end
  end
end
