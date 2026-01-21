defmodule EventasaurusApp.Venues.RegenerateSlugsByCityJob do
  @moduledoc """
  Oban worker for regenerating venue slugs for all venues in a specific city.

  This job is used when venue slugs need to be refreshed after initial city setup
  or when the slug generation logic has been updated.

  ## Parameters

  - `city_id` (required): The ID of the city whose venues should have slugs regenerated
  - `city_slug` (optional): City slug for display purposes in logs
  - `force_all` (optional, default: false): If true, regenerate all slugs even if unchanged

  ## Metadata Stored

  - `total_venues`: Total number of venues processed
  - `updated`: Number of venues with updated slugs
  - `skipped`: Number of venues where slug didn't change
  - `failed`: Number of venues that failed to update
  - `duration_seconds`: Time taken to complete job
  - `failed_venues`: Array of failed venue details for debugging

  ## Example

      # Queue job for London
      %{city_id: 123, city_slug: "london"}
      |> EventasaurusApp.Venues.RegenerateSlugsByCityJob.new()
      |> Oban.insert()

  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    priority: 2

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query
  require Logger

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_id" => city_id} = args}) do
    city_slug = args["city_slug"] || "unknown"
    force_all = args["force_all"] || false

    Logger.info("Starting venue slug regeneration for city_id=#{city_id} (#{city_slug})")

    start_time = System.monotonic_time(:second)

    # Verify city exists
    case JobRepo.get(City, city_id) do
      nil ->
        {:error, "City not found: #{city_id}"}

      city ->
        # Get total count for progress tracking
        total = count_city_venues(city_id)
        Logger.info("Found #{total} venues to process in #{city.name}")

        # Process venues in batches
        {updated, skipped, errors, failed_venues} =
          process_venues_in_batches(city_id, total, force_all)

        duration = System.monotonic_time(:second) - start_time

        Logger.info("""
        Venue slug regeneration complete for #{city.name}!
        - Total: #{total}
        - Updated: #{updated}
        - Skipped: #{skipped}
        - Errors: #{errors}
        - Duration: #{duration}s
        """)

        # Store results in job metadata
        {:ok,
         %{
           city_id: city_id,
           city_name: city.name,
           city_slug: city.slug,
           total_venues: total,
           updated: updated,
           skipped: skipped,
           failed: errors,
           duration_seconds: duration,
           failed_venues: failed_venues,
           completed_at: DateTime.utc_now()
         }}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    {:error, "Missing required parameter: city_id. Got: #{inspect(args)}"}
  end

  # Public API for enqueueing jobs

  @doc """
  Enqueue a slug regeneration job for a specific city.

  ## Examples

      iex> RegenerateSlugsByCityJob.enqueue(123, "london")
      {:ok, %Oban.Job{}}

      iex> RegenerateSlugsByCityJob.enqueue(123, "london", force_all: true)
      {:ok, %Oban.Job{}}

  """
  def enqueue(city_id, city_slug \\ nil, opts \\ []) do
    force_all = Keyword.get(opts, :force_all, false)

    %{
      city_id: city_id,
      city_slug: city_slug,
      force_all: force_all
    }
    |> new()
    |> Oban.insert()
  end

  # Private functions

  defp count_city_venues(city_id) do
    from(v in Venue,
      where: v.city_id == ^city_id,
      select: count(v.id)
    )
    |> JobRepo.one()
  end

  defp process_venues_in_batches(city_id, total, force_all) do
    # Calculate number of batches needed
    num_batches = ceil(total / @batch_size)

    # Process each batch
    0..(num_batches - 1)
    |> Enum.reduce({0, 0, 0, []}, fn batch_num, {updated, skipped, errors, failed_venues} ->
      offset = batch_num * @batch_size

      venues =
        from(v in Venue,
          where: v.city_id == ^city_id,
          order_by: [asc: v.id],
          limit: ^@batch_size,
          offset: ^offset,
          preload: [city_ref: :country]
        )
        |> JobRepo.all()

      # Process each venue in the batch within a transaction
      batch_result =
        JobRepo.transaction(fn ->
          Enum.reduce(venues, {0, 0, 0, []}, fn venue, {u, s, e, failed} ->
            case regenerate_venue_slug(venue, force_all) do
              {:ok, _} ->
                processed_so_far = offset + u + s + e + 1

                if rem(processed_so_far, 50) == 0 do
                  Logger.info("Processed #{processed_so_far}/#{total} venues...")
                end

                {u + 1, s, e, failed}

              {:skipped, _reason} ->
                {u, s + 1, e, failed}

              {:error, reason} ->
                Logger.warning(
                  "Failed to update venue #{venue.id} (#{venue.name}): #{inspect(reason)}"
                )

                failed_venue = %{
                  venue_id: venue.id,
                  venue_name: venue.name,
                  venue_slug: venue.slug,
                  error: format_error(reason)
                }

                {u, s, e + 1, [failed_venue | failed]}
            end
          end)
        end)

      # Extract result from transaction
      {batch_u, batch_s, batch_e, batch_failed} =
        case batch_result do
          {:ok, result} ->
            result

          {:error, _} ->
            # If transaction failed, count all venues in batch as errors
            {0, 0, length(venues), []}
        end

      {
        updated + batch_u,
        skipped + batch_s,
        errors + batch_e,
        failed_venues ++ batch_failed
      }
    end)
  end

  defp regenerate_venue_slug(venue, force_all) do
    # Directly generate new slug using the Slug module's build_slug function
    # This bypasses the maybe_generate_slug conditional logic
    changeset =
      venue
      |> Ecto.Changeset.change(%{})
      |> Ecto.Changeset.put_change(:city_id, venue.city_id)

    # Build new slug directly
    new_slug = Venue.Slug.build_slug([venue.name], changeset)

    # Create changeset with the new slug
    changeset_with_slug = Ecto.Changeset.put_change(changeset, :slug, new_slug)

    cond do
      is_nil(new_slug) ->
        {:error, "Slug generation returned nil"}

      new_slug == venue.slug && !force_all ->
        {:skipped, "Slug unchanged"}

      true ->
        case JobRepo.update(changeset_with_slug) do
          {:ok, updated_venue} ->
            Logger.debug("""
            Updated venue slug:
            - Venue: #{venue.name} (ID: #{venue.id})
            - Old: #{venue.slug}
            - New: #{updated_venue.slug}
            """)

            {:ok, updated_venue}

          {:error, changeset} ->
            {:error, changeset.errors}
        end
    end
  end

  defp format_error(errors) when is_list(errors) do
    errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
