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

      # Calculate category specificity metrics
      specificity_metrics = calculate_category_specificity(source_id)
      category_specificity = specificity_metrics.score

      quality_score =
        calculate_quality_score(
          venue_completeness,
          image_completeness,
          category_completeness,
          category_specificity,
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
        category_specificity: category_specificity,
        specificity_metrics: specificity_metrics,
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

  defp get_category_distribution(source_id) do
    # Get distribution of categories for events from this source
    # Returns list of maps with category_name, count, and percentage
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        join: pec in "public_event_categories",
        on: pec.event_id == e.id,
        join: c in "categories",
        on: c.id == pec.category_id,
        where: pes.source_id == ^source_id,
        group_by: [c.id, c.name],
        select: %{
          category_name: c.name,
          count: count(e.id)
        },
        order_by: [desc: count(e.id)]
      )

    results = Repo.all(query)
    total_events = Enum.reduce(results, 0, fn cat, acc -> cat.count + acc end)

    # Add percentage to each category
    Enum.map(results, fn cat ->
      percentage =
        if total_events > 0 do
          Float.round(cat.count / total_events * 100, 1)
        else
          0.0
        end

      Map.put(cat, :percentage, percentage)
    end)
  end

  defp count_generic_categories(source_id) do
    # Count events categorized with generic category names
    # Returns count of events in categories like "Other", "Miscellaneous", etc.
    generic_list = Application.get_env(:eventasaurus, :generic_categories, [])

    if Enum.empty?(generic_list) do
      0
    else
      # Convert to lowercase for case-insensitive matching
      generic_lower = Enum.map(generic_list, &String.downcase/1)

      query =
        from(e in PublicEvent,
          join: pes in PublicEventSource,
          on: pes.event_id == e.id,
          join: pec in "public_event_categories",
          on: pec.event_id == e.id,
          join: c in "categories",
          on: c.id == pec.category_id,
          where: pes.source_id == ^source_id,
          where: fragment("LOWER(?)", c.name) in ^generic_lower,
          select: count(fragment("DISTINCT ?", e.id))
        )

      Repo.one(query) || 0
    end
  end

  defp calculate_category_entropy(distribution, total_events) do
    # Calculate Shannon entropy for category distribution
    # Returns a diversity score from 0-100 where:
    # - 0 = all events in one category (no diversity)
    # - 100 = events perfectly distributed across all categories (maximum diversity)
    if total_events == 0 or Enum.empty?(distribution) do
      0
    else
      # Calculate Shannon entropy: H = -Σ(p_i * log2(p_i))
      entropy =
        distribution
        |> Enum.reduce(0, fn cat, acc ->
          p = cat.count / total_events

          if p > 0 do
            acc - p * :math.log2(p)
          else
            acc
          end
        end)

      # Normalize to 0-100 scale
      # Maximum entropy is log2(number of categories)
      max_entropy = :math.log2(length(distribution))

      if max_entropy > 0 do
        round(entropy / max_entropy * 100)
      else
        0
      end
    end
  end

  defp calculate_category_specificity(source_id) do
    # Calculate category specificity score combining:
    # - Generic category avoidance (60% weight)
    # - Category diversity (40% weight)
    # Returns map with score and detailed metrics
    total_events = count_events(source_id)

    if total_events == 0 do
      %{
        score: 100,
        generic_event_count: 0,
        generic_avoidance_score: 100,
        diversity_score: 100,
        total_categories: 0
      }
    else
      # Get category distribution
      distribution = get_category_distribution(source_id)

      # Count generic categories
      generic_count = count_generic_categories(source_id)

      # Calculate generic avoidance score (0-100)
      # 100% = no generic categories, 0% = all events in generic categories
      generic_avoidance_score =
        if total_events > 0 do
          round((total_events - generic_count) / total_events * 100)
        else
          100
        end

      # Calculate diversity score using Shannon entropy
      # Note: distribution contains category assignment counts (can exceed total_events
      # since events can have multiple categories), so we need to calculate total
      # assignments separately for entropy calculation
      total_assignments = Enum.reduce(distribution, 0, fn cat, acc -> cat.count + acc end)
      diversity_score = calculate_category_entropy(distribution, total_assignments)

      # Calculate final specificity score
      # Generic avoidance: 60%, Diversity: 40%
      specificity_score = round(generic_avoidance_score * 0.6 + diversity_score * 0.4)

      %{
        score: specificity_score,
        generic_event_count: generic_count,
        generic_avoidance_score: generic_avoidance_score,
        diversity_score: diversity_score,
        total_categories: length(distribution)
      }
    end
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
         category_specificity,
         translation_completeness
       ) do
    if translation_completeness do
      # Multilingual source: venues 25%, images 20%, categories 20%, specificity 20%, translations 15%
      (venue_completeness * 0.25 + image_completeness * 0.20 + category_completeness * 0.20 +
         category_specificity * 0.20 + translation_completeness * 0.15)
      |> round()
    else
      # Single-language source: venues 30%, images 25%, categories 20%, specificity 25%
      (venue_completeness * 0.30 + image_completeness * 0.25 + category_completeness * 0.20 +
         category_specificity * 0.25)
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
