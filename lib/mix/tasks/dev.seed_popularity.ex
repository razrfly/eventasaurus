defmodule Mix.Tasks.Dev.SeedPopularity do
  @moduledoc """
  Seeds fake PostHog popularity data for development testing.

  This task generates realistic view counts for events, movies, venues, and performers
  using a power-law distribution (few very popular, long tail of low views).

  ## Usage

      mix dev.seed_popularity              # Seed all entity types
      mix dev.seed_popularity --only events,movies
      mix dev.seed_popularity --clear      # Clear all popularity data first

  ## Distribution

  View counts follow a realistic power-law distribution:
  - 5% of entities: 50-200 views (very popular)
  - 10% of entities: 15-50 views (moderately popular)
  - 15% of entities: 5-15 views (some interest)
  - 20% of entities: 1-5 views (low views)
  - 50% of entities: NULL/never synced (matches production where most pages have no data)

  ## Options

    * `--only` - Comma-separated list of entity types (events, movies, venues, performers)
    * `--clear` - Clear existing popularity data before seeding
    * `--quiet` - Suppress output messages

  ## Safety

  This task only runs in development and test environments.
  """

  use Mix.Task

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  @shortdoc "Seeds fake popularity data for development"

  @requirements ["app.config"]

  @entity_types ~w(events movies venues performers)

  @impl Mix.Task
  def run(args) do
    # Safety check - only dev/test
    unless Mix.env() in [:dev, :test] do
      Mix.raise("This task should only be run in development or test environments!")
    end

    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          only: :string,
          clear: :boolean,
          quiet: :boolean
        ]
      )

    Mix.Task.run("app.start")

    quiet = opts[:quiet] || false
    entity_types = parse_entity_types(opts[:only])

    if opts[:clear] do
      clear_popularity_data(entity_types, quiet)
    end

    seed_popularity_data(entity_types, quiet)

    unless quiet do
      IO.puts("\n✅ Popularity seeding complete!")
    end
  end

  defp parse_entity_types(nil), do: @entity_types

  defp parse_entity_types(only_string) do
    only_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @entity_types))
  end

  defp clear_popularity_data(entity_types, quiet) do
    unless quiet, do: IO.puts("\n🧹 Clearing existing popularity data...")

    Enum.each(entity_types, fn type ->
      {schema, name} = get_schema_info(type)
      {count, _} = Repo.update_all(schema, set: [posthog_view_count: 0, posthog_synced_at: nil])
      unless quiet, do: IO.puts("   Cleared #{count} #{name}")
    end)
  end

  defp seed_popularity_data(entity_types, quiet) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(entity_types, fn type ->
      {schema, name} = get_schema_info(type)
      seed_entity_type(schema, name, now, quiet)
    end)
  end

  defp get_schema_info("events"), do: {PublicEvent, "events"}
  defp get_schema_info("movies"), do: {Movie, "movies"}
  defp get_schema_info("venues"), do: {Venue, "venues"}
  defp get_schema_info("performers"), do: {Performer, "performers"}

  defp seed_entity_type(schema, name, now, quiet) do
    # Get all entity IDs
    ids = Repo.all(from(e in schema, select: e.id))
    total = length(ids)

    if total == 0 do
      unless quiet, do: IO.puts("\n📊 No #{name} found to seed")
      :ok
    else
      unless quiet, do: IO.puts("\n📊 Seeding #{total} #{name}...")

      # Shuffle and distribute according to power law
      shuffled_ids = Enum.shuffle(ids)
      distributions = calculate_distributions(total)

      updates =
        shuffled_ids
        |> Enum.with_index()
        |> Enum.map(fn {id, index} ->
          view_count = generate_view_count(index, distributions)
          {id, view_count}
        end)

      # Batch update
      updated_count = batch_update_view_counts(schema, updates, now)

      unless quiet do
        stats = calculate_stats(updates)

        IO.puts("   Updated: #{updated_count} #{name} (#{stats.no_data} left without data)")
        IO.puts("   Distribution:")
        IO.puts("     Very popular (50-200): #{stats.very_popular}")
        IO.puts("     Moderate (15-50): #{stats.moderate}")
        IO.puts("     Some interest (5-15): #{stats.some_interest}")
        IO.puts("     Low (1-5): #{stats.low}")
        IO.puts("     No data (NULL): #{stats.no_data}")
      end

      :ok
    end
  end

  defp calculate_distributions(total) do
    %{
      # 5% very popular
      very_popular_end: round(total * 0.05),
      # 10% moderate (5% + 10% = 15%)
      moderate_end: round(total * 0.15),
      # 15% some interest (15% + 15% = 30%)
      some_interest_end: round(total * 0.30),
      # 20% low views (30% + 20% = 50%)
      low_end: round(total * 0.50)
      # Remaining 50% are NULL/never synced (like production)
    }
  end

  defp generate_view_count(index, distributions) do
    cond do
      # 5% - Very popular: 50-200 views
      index < distributions.very_popular_end ->
        Enum.random(50..200)

      # 10% - Moderate: 15-50 views
      index < distributions.moderate_end ->
        Enum.random(15..50)

      # 15% - Some interest: 5-15 views
      index < distributions.some_interest_end ->
        Enum.random(5..15)

      # 20% - Low views: 1-5 views
      index < distributions.low_end ->
        Enum.random(1..5)

      # 50% - NULL/never synced (matches production reality)
      true ->
        nil
    end
  end

  defp batch_update_view_counts(schema, updates, now) do
    # Filter out nil values - those entities stay without popularity data
    updates_with_values = Enum.reject(updates, fn {_id, count} -> is_nil(count) end)

    # Update in chunks to avoid overwhelming the database
    updates_with_values
    |> Enum.chunk_every(100)
    |> Enum.map(fn chunk ->
      Enum.reduce(chunk, 0, fn {id, view_count}, acc ->
        {count, _} =
          Repo.update_all(
            from(e in schema, where: e.id == ^id),
            set: [posthog_view_count: view_count, posthog_synced_at: now]
          )

        acc + count
      end)
    end)
    |> Enum.sum()
  end

  defp calculate_stats(updates) do
    Enum.reduce(updates, %{very_popular: 0, moderate: 0, some_interest: 0, low: 0, no_data: 0}, fn {_id, count}, acc ->
      cond do
        is_nil(count) -> Map.update!(acc, :no_data, &(&1 + 1))
        count >= 50 -> Map.update!(acc, :very_popular, &(&1 + 1))
        count >= 15 -> Map.update!(acc, :moderate, &(&1 + 1))
        count >= 5 -> Map.update!(acc, :some_interest, &(&1 + 1))
        true -> Map.update!(acc, :low, &(&1 + 1))
      end
    end)
  end
end
