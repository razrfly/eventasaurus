defmodule EventasaurusDiscovery.Admin.DataQualityChecker do
  @moduledoc """
  Module for checking data quality and completeness for discovery sources.

  Tracks:
  - Missing venues
  - Missing images
  - Missing categories
  - Translation completeness (for multilingual sources)
  - Overall quality score

  Quality score is calculated as a weighted average:
  - For single-language sources: venues 40%, images 30%, categories 30%
  - For multilingual sources: venues 30%, images 25%, categories 25%, translations 20%
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
  - not_found: true when the source slug does not exist
  """
  def check_quality(source_slug) when is_binary(source_slug) do
    case get_source_id(source_slug) do
      nil ->
        %{
          total_events: 0,
          missing_venues: 0,
          missing_images: 0,
          missing_categories: 0,
          quality_score: 0,
          venue_completeness: 0,
          image_completeness: 0,
          category_completeness: 0,
          not_found: true
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
        category_completeness: 100,
        supports_translations: false
      }
    else
      missing_venues = count_missing_venues(source_id)
      missing_images = count_missing_images(source_id)
      missing_categories = count_missing_categories(source_id)

      # Check if this source supports translations
      has_translations = supports_translations?(source_id)

      # Calculate translation metrics if applicable
      {translation_completeness, missing_translations, genuine_translations,
       duplicate_translations} =
        if has_translations do
          multilingual = count_multilingual_events(source_id)
          genuine = count_genuine_translations(source_id)
          duplicates = count_duplicate_translations(source_id)
          # "Missing" means events without multilingual translations (single-language events are considered missing)
          missing = total_events - multilingual
          completeness = calculate_completeness(total_events, missing)
          {completeness, missing, genuine, duplicates}
        else
          {nil, nil, nil, nil}
        end

      venue_completeness = calculate_completeness(total_events, missing_venues)
      image_completeness = calculate_completeness(total_events, missing_images)
      category_completeness = calculate_completeness(total_events, missing_categories)

      quality_score =
        calculate_quality_score(
          venue_completeness,
          image_completeness,
          category_completeness,
          translation_completeness
        )

      %{
        total_events: total_events,
        missing_venues: missing_venues,
        missing_images: missing_images,
        missing_categories: missing_categories,
        missing_translations: missing_translations,
        genuine_translations: genuine_translations,
        duplicate_translations: duplicate_translations,
        quality_score: quality_score,
        venue_completeness: venue_completeness,
        image_completeness: image_completeness,
        category_completeness: category_completeness,
        translation_completeness: translation_completeness,
        supports_translations: has_translations
      }
    end
  end

  @doc """
  Get quality improvement recommendations for a source.

  Returns a list of recommendation strings based on data quality issues.
  Returns empty list if source not found.
  """
  def get_recommendations(source_slug) when is_binary(source_slug) do
    quality = check_quality(source_slug)

    if Map.get(quality, :not_found, false) do
      []
    else
      thresholds = get_quality_thresholds()
      recommendations = []

      recommendations =
        if quality.venue_completeness < thresholds.venue_completeness do
          [
            "Improve venue matching - #{quality.missing_venues} events missing venues"
            | recommendations
          ]
        else
          recommendations
        end

      recommendations =
        if quality.image_completeness < thresholds.image_completeness do
          [
            "Add more event images - #{quality.missing_images} events missing images"
            | recommendations
          ]
        else
          recommendations
        end

      recommendations =
        if quality.category_completeness < thresholds.category_completeness do
          [
            "Improve category classification - #{quality.missing_categories} events missing categories"
            | recommendations
          ]
        else
          recommendations
        end

      # Add translation recommendations if source supports translations
      recommendations =
        if quality.supports_translations && quality.translation_completeness &&
             quality.translation_completeness < thresholds.translation_completeness do
          msg =
            if quality.duplicate_translations && quality.duplicate_translations > 0 do
              "Improve translation coverage - #{quality.missing_translations} events missing translations (#{quality.duplicate_translations} have duplicate translations)"
            else
              "Improve translation coverage - #{quality.missing_translations} events missing translations"
            end

          [msg | recommendations]
        else
          recommendations
        end

      # Add quality warning if many duplicate translations exist
      recommendations =
        if quality.supports_translations && quality.duplicate_translations &&
             quality.duplicate_translations > 0 &&
             quality.genuine_translations &&
             quality.duplicate_translations > quality.genuine_translations do
          [
            "Translation quality issue - #{quality.duplicate_translations} events have identical text in multiple languages"
            | recommendations
          ]
        else
          recommendations
        end

      if Enum.empty?(recommendations), do: ["Data quality is excellent! 🎉"], else: recommendations
    end
  end

  @doc """
  Get quality status indicator (emoji and text) based on quality score.
  """
  def quality_status(quality_score) when is_integer(quality_score) do
    thresholds = get_quality_thresholds()

    cond do
      quality_score >= thresholds.excellent_score -> {"🟢", "Excellent", "text-green-600"}
      quality_score >= thresholds.good_score -> {"🟡", "Good", "text-yellow-600"}
      quality_score >= thresholds.fair_score -> {"🟠", "Fair", "text-orange-600"}
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

  defp count_multilingual_events(source_id) do
    # Count events that have multiple languages in title_translations OR description_translations
    # Uses jsonb_object_keys() to count the number of language keys
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        where: pes.source_id == ^source_id,
        where:
          (not is_nil(e.title_translations) and
             fragment("jsonb_typeof(?) = 'object'", e.title_translations) and
             fragment(
               "(SELECT COUNT(*) FROM jsonb_object_keys(?)) > 1",
               e.title_translations
             )) or
            (not is_nil(pes.description_translations) and
               fragment("jsonb_typeof(?) = 'object'", pes.description_translations) and
               fragment(
                 "(SELECT COUNT(*) FROM jsonb_object_keys(?)) > 1",
                 pes.description_translations
               )),
        select: count(pes.id)
      )

    Repo.one(query) || 0
  end

  defp count_single_language_events(source_id) do
    # Count events that have exactly one language in title_translations OR description_translations
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        where: pes.source_id == ^source_id,
        where:
          (not is_nil(e.title_translations) and
             fragment("jsonb_typeof(?) = 'object'", e.title_translations) and
             fragment(
               "(SELECT COUNT(*) FROM jsonb_object_keys(?)) = 1",
               e.title_translations
             )) or
            (not is_nil(pes.description_translations) and
               fragment("jsonb_typeof(?) = 'object'", pes.description_translations) and
               fragment(
                 "(SELECT COUNT(*) FROM jsonb_object_keys(?)) = 1",
                 pes.description_translations
               )),
        select: count(pes.id)
      )

    Repo.one(query) || 0
  end

  defp count_genuine_translations(source_id) do
    # Count events that have multiple languages with DIFFERENT text values
    # This filters out cases like {"en": "Poluzjanci", "pl": "Poluzjanci"}
    # Uses PostgreSQL to compare that not all values in the JSONB are identical
    # Checks both title_translations AND description_translations
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        where: pes.source_id == ^source_id,
        where:
          (not is_nil(e.title_translations) and
             fragment("jsonb_typeof(?) = 'object'", e.title_translations) and
             fragment(
               "(SELECT COUNT(*) FROM jsonb_object_keys(?)) > 1",
               e.title_translations
             ) and
             fragment(
               "(SELECT COUNT(DISTINCT value) FROM jsonb_each_text(?)) > 1",
               e.title_translations
             )) or
            (not is_nil(pes.description_translations) and
               fragment("jsonb_typeof(?) = 'object'", pes.description_translations) and
               fragment(
                 "(SELECT COUNT(*) FROM jsonb_object_keys(?)) > 1",
                 pes.description_translations
               ) and
               fragment(
                 "(SELECT COUNT(DISTINCT value) FROM jsonb_each_text(?)) > 1",
                 pes.description_translations
               )),
        select: count(pes.id)
      )

    Repo.one(query) || 0
  end

  defp count_duplicate_translations(source_id) do
    # Count events that have multiple language keys but identical text
    # E.g., {"en": "Band Name", "pl": "Band Name"}
    # Checks both title_translations AND description_translations
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        where: pes.source_id == ^source_id,
        where:
          (not is_nil(e.title_translations) and
             fragment("jsonb_typeof(?) = 'object'", e.title_translations) and
             fragment(
               "(SELECT COUNT(*) FROM jsonb_object_keys(?)) > 1",
               e.title_translations
             ) and
             fragment(
               "(SELECT COUNT(DISTINCT value) FROM jsonb_each_text(?)) = 1",
               e.title_translations
             )) or
            (not is_nil(pes.description_translations) and
               fragment("jsonb_typeof(?) = 'object'", pes.description_translations) and
               fragment(
                 "(SELECT COUNT(*) FROM jsonb_object_keys(?)) > 1",
                 pes.description_translations
               ) and
               fragment(
                 "(SELECT COUNT(DISTINCT value) FROM jsonb_each_text(?)) = 1",
                 pes.description_translations
               )),
        select: count(pes.id)
      )

    Repo.one(query) || 0
  end

  defp supports_translations?(source_id) do
    # Check if this source is configured to support multilingual content
    # For now, we'll check if any events from this source have multiple languages
    # This can be enhanced later with explicit source configuration
    count_multilingual_events(source_id) > 0
  end

  defp calculate_completeness(total, missing) do
    if total == 0 do
      100
    else
      ((total - missing) / total * 100) |> round()
    end
  end

  defp calculate_quality_score(
         venue_completeness,
         image_completeness,
         category_completeness,
         translation_completeness \\ nil
       ) do
    if translation_completeness do
      # Multilingual source: venues 30%, images 25%, categories 25%, translations 20%
      (venue_completeness * 0.3 + image_completeness * 0.25 + category_completeness * 0.25 +
         translation_completeness * 0.2)
      |> round()
    else
      # Single-language source: venues 40%, images 30%, categories 30%
      (venue_completeness * 0.4 + image_completeness * 0.3 + category_completeness * 0.3)
      |> round()
    end
  end

  defp get_quality_thresholds do
    config = Application.get_env(:eventasaurus_discovery, :quality_thresholds, [])

    %{
      venue_completeness: Keyword.get(config, :venue_completeness, 90),
      image_completeness: Keyword.get(config, :image_completeness, 80),
      category_completeness: Keyword.get(config, :category_completeness, 85),
      translation_completeness: Keyword.get(config, :translation_completeness, 80),
      excellent_score: Keyword.get(config, :excellent_score, 90),
      good_score: Keyword.get(config, :good_score, 75),
      fair_score: Keyword.get(config, :fair_score, 60)
    }
  end
end
