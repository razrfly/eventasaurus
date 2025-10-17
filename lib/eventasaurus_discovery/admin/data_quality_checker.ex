defmodule EventasaurusDiscovery.Admin.DataQualityChecker do
  @moduledoc """
  Module for checking data quality and completeness for discovery sources.

  Tracks:
  - Missing venues
  - Missing images
  - Missing categories
  - Overall quality score

  Quality score is calculated as a weighted average:
  - Venue completeness: 40%
  - Image completeness: 30%
  - Category completeness: 30%
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source

  @doc """
  Check data quality for a source by slug.

  Returns a map with:
  - total_events: Total events for this source
  - missing_venues: Count of events without venues
  - missing_images: Count of events without images
  - missing_categories: Count of events without categories
  - quality_score: Overall quality score (0-100)
  - venue_completeness: Venue data completeness percentage
  - image_completeness: Image data completeness percentage
  - category_completeness: Category data completeness percentage
  """
  def check_quality(source_slug) when is_binary(source_slug) do
    case get_source_id(source_slug) do
      nil ->
        %{
          total_events: 0,
          missing_venues: 0,
          missing_images: 0,
          missing_categories: 0,
          quality_score: 100,
          venue_completeness: 100,
          image_completeness: 100,
          category_completeness: 100
        }

      source_id ->
        check_quality_by_id(source_id)
    end
  end

  @doc """
  Check data quality for a source by ID.
  """
  def check_quality_by_id(source_id) when is_integer(source_id) do
    total_events = count_events(source_id)

    if total_events == 0 do
      %{
        total_events: 0,
        missing_venues: 0,
        missing_images: 0,
        missing_categories: 0,
        quality_score: 100,
        venue_completeness: 100,
        image_completeness: 100,
        category_completeness: 100
      }
    else
      missing_venues = count_missing_venues(source_id)
      missing_images = count_missing_images(source_id)
      missing_categories = count_missing_categories(source_id)

      venue_completeness = calculate_completeness(total_events, missing_venues)
      image_completeness = calculate_completeness(total_events, missing_images)
      category_completeness = calculate_completeness(total_events, missing_categories)

      quality_score = calculate_quality_score(
        venue_completeness,
        image_completeness,
        category_completeness
      )

      %{
        total_events: total_events,
        missing_venues: missing_venues,
        missing_images: missing_images,
        missing_categories: missing_categories,
        quality_score: quality_score,
        venue_completeness: venue_completeness,
        image_completeness: image_completeness,
        category_completeness: category_completeness
      }
    end
  end

  @doc """
  Get quality improvement recommendations for a source.

  Returns a list of recommendation strings based on data quality issues.
  """
  def get_recommendations(source_slug) when is_binary(source_slug) do
    quality = check_quality(source_slug)
    recommendations = []

    recommendations =
      if quality.venue_completeness < 90 do
        ["Improve venue matching - #{quality.missing_venues} events missing venues" | recommendations]
      else
        recommendations
      end

    recommendations =
      if quality.image_completeness < 80 do
        ["Add more event images - #{quality.missing_images} events missing images" | recommendations]
      else
        recommendations
      end

    recommendations =
      if quality.category_completeness < 85 do
        ["Improve category classification - #{quality.missing_categories} events missing categories" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["Data quality is excellent! 🎉"]
    else
      recommendations
    end
  end

  @doc """
  Get quality status indicator (emoji and text) based on quality score.
  """
  def quality_status(quality_score) when is_integer(quality_score) do
    cond do
      quality_score >= 90 -> {"🟢", "Excellent", "text-green-600"}
      quality_score >= 75 -> {"🟡", "Good", "text-yellow-600"}
      quality_score >= 60 -> {"🟠", "Fair", "text-orange-600"}
      true -> {"🔴", "Poor", "text-red-600"}
    end
  end

  # Private functions

  defp get_source_id(source_slug) do
    query =
      from(s in Source,
        where: s.slug == ^source_slug,
        select: s.id
      )

    Repo.one(query)
  end

  defp count_events(source_id) do
    query =
      from(pes in PublicEventSource,
        where: pes.source_id == ^source_id,
        select: count(pes.id)
      )

    Repo.one(query) || 0
  end

  defp count_missing_venues(source_id) do
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        where: pes.source_id == ^source_id,
        where: is_nil(e.venue_id),
        select: count(e.id)
      )

    Repo.one(query) || 0
  end

  defp count_missing_images(source_id) do
    query =
      from(pes in PublicEventSource,
        where: pes.source_id == ^source_id,
        where: is_nil(pes.image_url) or pes.image_url == "",
        select: count(pes.id)
      )

    Repo.one(query) || 0
  end

  defp count_missing_categories(source_id) do
    # Count events that have no categories in the join table
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        left_join: pec in "public_event_categories",
        on: pec.event_id == e.id,
        where: pes.source_id == ^source_id,
        where: is_nil(pec.category_id),
        select: count(fragment("DISTINCT ?", e.id))
      )

    Repo.one(query) || 0
  end

  defp calculate_completeness(total, missing) do
    if total == 0 do
      100
    else
      ((total - missing) / total * 100) |> round()
    end
  end

  defp calculate_quality_score(venue_completeness, image_completeness, category_completeness) do
    # Weighted average: venues 40%, images 30%, categories 30%
    (venue_completeness * 0.4 + image_completeness * 0.3 + category_completeness * 0.3)
    |> round()
  end
end
