defmodule EventasaurusDiscovery.Sources.Pubquiz.Jobs.CityJob do
  @moduledoc """
  Processes a single Polish city from PubQuiz.pl.

  Fetches venue listings for the city and schedules VenueDetailJob for each venue.
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.Pubquiz.{
    Client,
    VenueExtractor,
    Jobs.VenueDetailJob
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_url" => city_url, "source_id" => source_id}}) do
    # Extract city name from URL (e.g., "katowice" from "/kategoria-produktu/katowice/")
    city_name = extract_city_name_from_url(city_url)
    Logger.info("🏙️ Processing PubQuiz city: #{city_name}")

    with {:ok, html} <- Client.fetch_city_page(city_url),
         venues <- VenueExtractor.extract_venues(html),
         venues <- filter_valid_venues(venues),
         scheduled_count <- schedule_venue_jobs(venues, source_id, city_name) do
      Logger.info("""
      ✅ City job completed: #{city_name}
      Venues found: #{length(venues)}
      Venue jobs scheduled: #{scheduled_count}
      """)

      {:ok,
       %{
         city: city_name,
         venues_found: length(venues),
         jobs_scheduled: scheduled_count
       }}
    else
      {:error, reason} = error ->
        Logger.error("❌ City job failed for #{city_name}: #{inspect(reason)}")
        error
    end
  end

  defp extract_city_name_from_url(url) do
    # Extract city name from URL like "/kategoria-produktu/katowice/"
    case String.split(url, "/") |> Enum.reject(&(&1 == "")) do
      [] -> "Unknown"
      segments -> segments |> List.last() |> String.trim() |> String.capitalize()
    end
  end

  defp filter_valid_venues(venues) do
    Enum.filter(venues, fn venue ->
      # Must have name and URL
      is_valid =
        is_binary(venue.name) &&
          String.trim(venue.name) != "" &&
          is_binary(venue.url) &&
          String.trim(venue.url) != ""

      if not is_valid do
        Logger.warning("⚠️ Skipping invalid venue: #{inspect(venue)}")
      end

      is_valid
    end)
  end

  defp schedule_venue_jobs(venues, source_id, city_name) do
    venues
    |> Enum.with_index()
    |> Enum.map(fn {venue, index} ->
      # Stagger venue jobs to respect rate limits (3 seconds between requests)
      delay_seconds = index * 3
      scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

      job_args = %{
        "venue_url" => venue.url,
        "venue_name" => venue.name,
        "venue_image_url" => venue.image_url,
        "source_id" => source_id,
        "city_name" => city_name
      }

      VenueDetailJob.new(job_args, scheduled_at: scheduled_at)
      |> Oban.insert()
    end)
    |> Enum.count(fn
      {:ok, _} -> true
      _ -> false
    end)
  end
end
