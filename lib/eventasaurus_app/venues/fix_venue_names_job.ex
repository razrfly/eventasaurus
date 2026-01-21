defmodule EventasaurusApp.Venues.FixVenueNamesJob do
  @moduledoc """
  Oban job for fixing venue names using geocoding metadata.

  This job uses VenueNameValidator to assess and fix venue names that don't match
  their geocoded names. It processes venues in batches and regenerates slugs.

  ## Arguments

  - `city_id` (required) - The ID of the city to process venues for
  - `severity` (optional) - Filter by severity: "all" (default), "moderate", or "severe"

  ## Usage

      %{city_id: 6, severity: "all"}
      |> FixVenueNamesJob.new()
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :venue,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :worker]]

  require Logger
  import Ecto.Query
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Validation.VenueNameValidator

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_id = Map.fetch!(args, "city_id")
    severity = Map.get(args, "severity", "all") |> parse_severity()

    Logger.info("Starting venue name fix job for city_id=#{city_id}, severity=#{severity}")

    # 1. Find venues with metadata
    venues = find_venues_with_metadata(city_id)
    Logger.info("Found #{length(venues)} venues with metadata")

    # 2. Assess each venue using VenueNameValidator
    assessments = assess_all_venues(venues, severity)
    needs_fix = Enum.count(assessments, & &1.needs_fix)
    Logger.info("#{needs_fix} venues need fixing (severity: #{severity})")

    # 3. Fix venues in batches
    fixed_count =
      assessments
      |> Enum.filter(& &1.needs_fix)
      |> Enum.chunk_every(50)
      |> Enum.map(&fix_venue_batch/1)
      |> Enum.sum()

    Logger.info("Fixed #{fixed_count} venue names")

    {:ok, %{fixed: fixed_count, total: length(venues), assessed: needs_fix}}
  end

  # Find all venues in city that have geocoding metadata
  defp find_venues_with_metadata(city_id) do
    from(v in Venue,
      where: v.city_id == ^city_id,
      where: not is_nil(v.metadata),
      preload: [:city_ref]
    )
    |> JobRepo.all()
  end

  # Assess all venues and determine which need fixing
  defp assess_all_venues(venues, severity_filter) do
    Enum.map(venues, fn venue ->
      assess_venue(venue, severity_filter)
    end)
  end

  # Assess a single venue using VenueNameValidator
  defp assess_venue(venue, severity_filter) do
    # Extract geocoded name from metadata
    geocoded_name = VenueNameValidator.extract_geocoded_name(venue.metadata)

    case geocoded_name do
      nil ->
        %{
          venue: venue,
          needs_fix: false,
          reason: :no_geocoded_name,
          geocoded_name: nil,
          similarity: nil
        }

      geocoded ->
        # Calculate similarity between current name and geocoded name
        similarity = VenueNameValidator.calculate_similarity(venue.name, geocoded)
        severity = determine_severity(similarity)

        # Check if this venue should be fixed based on severity filter
        should_fix = should_fix_venue?(severity, similarity, severity_filter)

        %{
          venue: venue,
          needs_fix: should_fix,
          reason: if(should_fix, do: :quality_issue, else: :acceptable),
          geocoded_name: geocoded,
          similarity: similarity,
          severity: severity
        }
    end
  end

  # Determine severity based on similarity score
  defp determine_severity(similarity) when similarity < 0.3, do: :severe
  defp determine_severity(similarity) when similarity < 0.7, do: :moderate
  defp determine_severity(_), do: :acceptable

  # Check if venue should be fixed based on severity filter
  defp should_fix_venue?(:severe, _similarity, severity_filter)
       when severity_filter in [:all, :moderate, :severe],
       do: true

  defp should_fix_venue?(:moderate, _similarity, severity_filter)
       when severity_filter in [:all, :moderate],
       do: true

  defp should_fix_venue?(:acceptable, _similarity, _severity_filter), do: false
  defp should_fix_venue?(_severity, _similarity, _severity_filter), do: false

  # Fix a batch of venues in a transaction
  defp fix_venue_batch(assessments) do
    case JobRepo.transaction(fn ->
           Enum.map(assessments, &fix_single_venue/1)
         end) do
      {:ok, results} ->
        # Count successful fixes
        Enum.count(results, &match?({:ok, _}, &1))

      {:error, reason} ->
        Logger.error("Batch transaction failed: #{inspect(reason)}")
        0
    end
  end

  # Fix a single venue's name and regenerate slug
  defp fix_single_venue(assessment) do
    venue = assessment.venue
    new_name = assessment.geocoded_name

    try do
      # Create changeset with new name and force slug regeneration
      changeset =
        venue
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:name, new_name)
        |> Ecto.Changeset.force_change(:name, new_name)
        |> Venue.Slug.maybe_generate_slug()

      # Update venue
      case JobRepo.update(changeset) do
        {:ok, updated_venue} ->
          Logger.debug(
            "Fixed venue ##{venue.id}: '#{venue.name}' → '#{updated_venue.name}' " <>
              "(slug: #{venue.slug} → #{updated_venue.slug})"
          )

          {:ok, updated_venue}

        {:error, changeset} ->
          Logger.warning("Failed to fix venue ##{venue.id}: #{inspect(changeset.errors)}")

          {:error, changeset.errors}
      end
    rescue
      error ->
        Logger.error("Exception fixing venue ##{venue.id}: #{inspect(error)}")

        {:error, :exception}
    end
  end

  # Parse severity filter from string
  defp parse_severity("severe"), do: :severe
  defp parse_severity("moderate"), do: :moderate
  defp parse_severity("all"), do: :all
  defp parse_severity(_), do: :all
end
