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
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Validation.VenueNameValidator

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
        category_specificity: 100,
        specificity_metrics: %{
          score: 100,
          generic_event_count: 0,
          generic_avoidance_score: 100,
          diversity_score: 100,
          total_categories: 0
        },
        price_completeness: 100,
        price_metrics: %{
          events_with_price_info: 0,
          events_free: 0,
          events_paid: 0,
          events_with_currency: 0,
          events_with_price_range: 0,
          unique_prices: 0,
          price_diversity_score: 100,
          price_diversity_warning: nil
        },
        description_quality: 100,
        description_metrics: %{
          has_description: 0,
          short_descriptions: 0,
          adequate_descriptions: 0,
          detailed_descriptions: 0,
          avg_length: 0
        },
        performer_completeness: 100,
        performer_metrics: %{
          events_with_performers: 0,
          events_single_performer: 0,
          events_multiple_performers: 0,
          total_performers: 0,
          avg_performers_per_event: 0.0
        },
        occurrence_richness: 100,
        occurrence_metrics: %{
          events_with_occurrences: 0,
          events_without_occurrences: 0,
          events_single_date: 0,
          events_multiple_dates: 0,
          avg_dates_per_event: 0.0,
          type_distribution: %{},
          validation_issues: %{
            pattern_missing_dates: 0,
            explicit_single_date: 0,
            exhibition_single_date: 0,
            total_validity_issues: 0
          },
          validity_score: 100,
          time_quality_metrics: %{
            time_quality: 100,
            total_occurrences: 0,
            midnight_count: 0,
            midnight_percentage: 0,
            most_common_time: nil,
            most_common_time_count: 0,
            same_time_percentage: 0,
            hour_distribution: %{},
            time_diversity_score: 100
          }
        },
        supports_translations: false
      }
    else
      missing_venues = count_missing_venues(source_id)
      missing_images = count_missing_images(source_id)
      missing_categories = count_missing_categories(source_id)

      # NEW: Calculate venue name quality
      {venues_with_low_quality_names, low_quality_examples} =
        count_venues_with_low_quality_names(source_id)

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

      # Calculate venue metrics (coverage + quality)
      events_with_venues = total_events - missing_venues
      venue_coverage = calculate_completeness(total_events, missing_venues)

      # Calculate venue name quality based on similarity to geocoded names
      venue_name_quality =
        if events_with_venues > 0 do
          calculate_completeness(events_with_venues, venues_with_low_quality_names)
        else
          100
        end

      # Combined venue quality score (50% coverage, 50% name quality)
      venue_quality = (venue_coverage * 0.5 + venue_name_quality * 0.5) |> round()

      # Keep old name for backwards compatibility
      venue_completeness = venue_quality
      image_completeness = calculate_completeness(total_events, missing_images)
      category_completeness = calculate_completeness(total_events, missing_categories)

      # Calculate category specificity metrics
      specificity_metrics = calculate_category_specificity(source_id)
      category_specificity = specificity_metrics.score

      # Calculate price completeness
      price_metrics = calculate_price_completeness(source_id)

      # Calculate description quality
      description_metrics = calculate_description_quality(source_id)

      # Calculate performer completeness
      performer_metrics = calculate_performer_completeness(source_id)

      # Calculate occurrence richness
      occurrence_metrics = calculate_occurrence_richness(source_id)

      # Calculate time quality
      time_quality_metrics = calculate_time_quality(source_id)

      quality_score =
        calculate_quality_score(
          venue_completeness,
          image_completeness,
          category_completeness,
          category_specificity,
          price_metrics.price_completeness,
          description_metrics.description_quality,
          performer_metrics.performer_completeness,
          occurrence_metrics.occurrence_richness,
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
        venue_coverage: venue_coverage,
        venue_name_quality: venue_name_quality,
        venue_quality: venue_quality,
        venues_with_low_quality_names: venues_with_low_quality_names,
        low_quality_venue_examples: low_quality_examples,
        image_completeness: image_completeness,
        category_completeness: category_completeness,
        category_specificity: category_specificity,
        specificity_metrics: specificity_metrics,
        price_completeness: price_metrics.price_completeness,
        price_metrics: %{
          events_with_price_info: price_metrics.events_with_price_info,
          events_free: price_metrics.events_free,
          events_paid: price_metrics.events_paid,
          events_with_currency: price_metrics.events_with_currency,
          events_with_price_range: price_metrics.events_with_price_range,
          unique_prices: price_metrics.unique_prices,
          price_diversity_score: price_metrics.price_diversity_score,
          price_diversity_warning: price_metrics.price_diversity_warning
        },
        description_quality: description_metrics.description_quality,
        description_metrics: %{
          has_description: description_metrics.has_description,
          short_descriptions: description_metrics.short_descriptions,
          adequate_descriptions: description_metrics.adequate_descriptions,
          detailed_descriptions: description_metrics.detailed_descriptions,
          avg_length: description_metrics.avg_length
        },
        performer_completeness: performer_metrics.performer_completeness,
        performer_metrics: %{
          events_with_performers: performer_metrics.events_with_performers,
          events_single_performer: performer_metrics.events_single_performer,
          events_multiple_performers: performer_metrics.events_multiple_performers,
          total_performers: performer_metrics.total_performers,
          avg_performers_per_event: performer_metrics.avg_performers_per_event
        },
        occurrence_richness: occurrence_metrics.occurrence_richness,
        occurrence_metrics: %{
          events_with_occurrences: occurrence_metrics.events_with_occurrences,
          events_without_occurrences: occurrence_metrics.events_without_occurrences,
          events_single_date: occurrence_metrics.events_single_date,
          events_multiple_dates: occurrence_metrics.events_multiple_dates,
          avg_dates_per_event: occurrence_metrics.avg_dates_per_event,
          type_distribution: occurrence_metrics.type_distribution,
          validation_issues: occurrence_metrics.validation_issues,
          validity_score: occurrence_metrics.validity_score,
          time_quality_metrics: time_quality_metrics
        },
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

      # Venue recommendations - check both coverage and quality
      recommendations =
        cond do
          # Coverage issue: missing venues
          quality.venue_coverage < thresholds.venue_completeness ->
            [
              "Improve venue matching - #{quality.missing_venues} events missing venues"
              | recommendations
            ]

          # Quality issue: low similarity with geocoded names
          quality.venue_name_quality < 80 ->
            msg =
              "Venue name quality issue - #{quality.venues_with_low_quality_names} venues have names that don't match geocoding data"

            # Add examples if available
            msg =
              if length(quality.low_quality_venue_examples) > 0 do
                examples =
                  quality.low_quality_venue_examples
                  |> Enum.take(3)
                  |> Enum.map(fn ex ->
                    sim = Float.round(ex.similarity, 2)
                    "\"#{ex.venue_name}\" vs \"#{ex.geocoded_name}\" (similarity: #{sim})"
                  end)
                  |> Enum.join(", ")

                "#{msg}: #{examples}"
              else
                msg
              end

            [msg | recommendations]

          true ->
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

      # Add price data recommendation if completeness is low
      recommendations =
        if quality.price_completeness < 70 do
          missing = quality.total_events - quality.price_metrics.events_with_price_info

          [
            "Add price information - #{missing} events missing price data"
            | recommendations
          ]
        else
          recommendations
        end

      # Add price diversity warning if present
      recommendations =
        if quality.price_metrics.price_diversity_warning do
          [
            "⚠️ #{quality.price_metrics.price_diversity_warning}"
            | recommendations
          ]
        else
          recommendations
        end

      # Add description quality recommendation if quality is low
      recommendations =
        if quality.description_quality < 60 do
          missing = quality.total_events - quality.description_metrics.has_description

          [
            "Improve event descriptions - #{missing} events missing descriptions, #{quality.description_metrics.short_descriptions} too short"
            | recommendations
          ]
        else
          recommendations
        end

      # Add performer data recommendation if completeness is low
      recommendations =
        if quality.performer_completeness < 50 do
          missing = quality.total_events - quality.performer_metrics.events_with_performers

          [
            "Add performer information - #{missing} events missing artist/performer data"
            | recommendations
          ]
        else
          recommendations
        end

      # Add occurrence richness recommendation if richness is low
      recommendations =
        if quality.occurrence_richness < 70 do
          missing = quality.occurrence_metrics.events_without_occurrences

          [
            "Improve occurrence data - #{missing} events missing occurrence information"
            | recommendations
          ]
        else
          recommendations
        end

      # Add occurrence validity warning if there are structural issues
      recommendations =
        if quality.occurrence_metrics.validity_score < 80 do
          issues = quality.occurrence_metrics.validation_issues

          msg =
            "⚠️ Occurrence data issues: #{issues.pattern_missing_dates} pattern events missing recurrence rules, #{issues.explicit_single_date} explicit events with single date"

          [msg | recommendations]
        else
          recommendations
        end

      # Add time quality warning if there are suspicious time patterns
      recommendations =
        if quality.occurrence_metrics.time_quality_metrics.time_quality < 70 do
          metrics = quality.occurrence_metrics.time_quality_metrics

          msg =
            cond do
              metrics.midnight_percentage > 50 ->
                "⚠️ Time parsing issues: #{Float.round(metrics.midnight_percentage, 1)}% of events at midnight (00:00) - likely missing time parsing"

              metrics.same_time_percentage > 80 ->
                "⚠️ Suspicious time pattern: #{Float.round(metrics.same_time_percentage, 1)}% of events at #{metrics.most_common_time} - check for hardcoded times"

              metrics.time_diversity_score < 50 ->
                "⚠️ Low time diversity: score #{metrics.time_diversity_score}/100 - verify time extraction is working correctly"

              true ->
                "⚠️ Time quality issues detected - review time parsing implementation (score: #{metrics.time_quality}/100)"
            end

          [msg | recommendations]
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

  defp count_venues_with_low_quality_names(source_id) do
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        join: v in Venue,
        on: v.id == e.venue_id,
        where: pes.source_id == ^source_id,
        where: not is_nil(e.venue_id),
        where: not is_nil(v.metadata),
        select: %{
          event_id: e.id,
          venue_id: v.id,
          venue_name: v.name,
          metadata: v.metadata
        }
      )

    # Get all events with venues that have metadata
    events_with_venues = Repo.all(query)

    # Calculate how many unique venues have low-quality names
    {low_quality_ids, examples_by_venue} =
      events_with_venues
      |> Enum.reduce({MapSet.new(), %{}}, fn event, {ids, examples} ->
        case VenueNameValidator.validate_against_geocoded(event.venue_name, event.metadata) do
          {:error, :low_similarity, similarity} ->
            geocoded_name = VenueNameValidator.extract_geocoded_name(event.metadata)

            example = %{
              venue_id: event.venue_id,
              venue_name: event.venue_name,
              geocoded_name: geocoded_name,
              similarity: similarity,
              severity: :severe
            }

            {
              MapSet.put(ids, event.venue_id),
              Map.put_new(examples, event.venue_id, example)
            }

          {:warning, :moderate_similarity, similarity} ->
            # Moderate similarity also counts as quality issue (but less severe)
            geocoded_name = VenueNameValidator.extract_geocoded_name(event.metadata)

            example = %{
              venue_id: event.venue_id,
              venue_name: event.venue_name,
              geocoded_name: geocoded_name,
              similarity: similarity,
              severity: :moderate
            }

            {
              MapSet.put(ids, event.venue_id),
              Map.put_new(examples, event.venue_id, example)
            }

          _ ->
            {ids, examples}
        end
      end)

    # Return count of unique venues and first 5 examples
    {MapSet.size(low_quality_ids), examples_by_venue |> Map.values() |> Enum.take(5)}
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

  # Calculate price data completeness.
  #
  # Measures how well pricing information is populated:
  # - Events with any price info (min_price OR is_free)
  # - Currency presence
  # - Price range completeness
  # - Free vs paid breakdown
  # - Price diversity (detects if all prices are identical)
  #
  # Returns map with completeness score and detailed metrics.
  defp calculate_price_completeness(source_id) do
    query =
      from(pes in PublicEventSource,
        where: pes.source_id == ^source_id,
        select: %{
          total: count(pes.id),
          has_price_info:
            fragment(
              "COUNT(CASE WHEN ? IS NOT NULL OR ? IS NOT NULL OR ? = true THEN 1 END)",
              pes.min_price,
              pes.max_price,
              pes.is_free
            ),
          has_currency:
            fragment(
              "COUNT(CASE WHEN ? IS NOT NULL THEN 1 END)",
              pes.currency
            ),
          has_min_price:
            fragment(
              "COUNT(CASE WHEN ? IS NOT NULL THEN 1 END)",
              pes.min_price
            ),
          has_max_price:
            fragment(
              "COUNT(CASE WHEN ? IS NOT NULL THEN 1 END)",
              pes.max_price
            ),
          has_price_range:
            fragment(
              "COUNT(CASE WHEN ? IS NOT NULL AND ? IS NOT NULL THEN 1 END)",
              pes.min_price,
              pes.max_price
            ),
          is_free_count:
            fragment(
              "COUNT(CASE WHEN ? = true THEN 1 END)",
              pes.is_free
            )
        }
      )

    stats = Repo.one(query)

    if stats.total == 0 do
      %{
        price_completeness: 100,
        total_events: 0,
        events_with_price_info: 0,
        events_free: 0,
        events_paid: 0,
        events_with_currency: 0,
        events_with_price_range: 0,
        unique_prices: 0,
        price_diversity_score: 100,
        price_diversity_warning: nil
      }
    else
      # Price completeness = % of events with ANY price information
      price_completeness = round(stats.has_price_info / stats.total * 100)

      # Calculate price diversity for paid events
      {unique_prices, price_diversity_score, price_diversity_warning} =
        calculate_price_diversity(source_id, stats.has_min_price)

      %{
        price_completeness: price_completeness,
        total_events: stats.total,
        events_with_price_info: stats.has_price_info,
        events_free: stats.is_free_count,
        events_paid: stats.has_min_price,
        events_with_currency: stats.has_currency,
        events_with_price_range: stats.has_price_range,
        unique_prices: unique_prices,
        price_diversity_score: price_diversity_score,
        price_diversity_warning: price_diversity_warning
      }
    end
  end

  # Calculate price diversity metrics to detect if prices are too uniform
  # (e.g., scraper hardcoded all prices to the same value)
  #
  # Returns {unique_count, diversity_score, warning_message}
  defp calculate_price_diversity(source_id, paid_event_count) do
    if paid_event_count == 0 do
      # No paid events, diversity is N/A
      {0, 100, nil}
    else
      # Get distribution of prices (only for paid events)
      price_query =
        from(pes in PublicEventSource,
          where: pes.source_id == ^source_id,
          where: not is_nil(pes.min_price),
          group_by: pes.min_price,
          select: %{
            price: pes.min_price,
            count: count(pes.id)
          },
          order_by: [desc: count(pes.id)]
        )

      price_distribution = Repo.all(price_query)
      unique_prices = length(price_distribution)

      # Calculate diversity score and warning
      cond do
        # All prices are identical
        unique_prices == 1 ->
          {1, 0,
           "All #{paid_event_count} paid events have identical price (#{List.first(price_distribution).price})"}

        # Low diversity: >80% of events have the same price
        unique_prices >= 2 ->
          top_price = List.first(price_distribution)
          top_percentage = top_price.count / paid_event_count * 100

          cond do
            top_percentage > 90 ->
              {unique_prices, 10,
               "#{round(top_percentage)}% of paid events (#{top_price.count}/#{paid_event_count}) have identical price (#{top_price.price})"}

            top_percentage > 80 ->
              {unique_prices, 25,
               "#{round(top_percentage)}% of paid events (#{top_price.count}/#{paid_event_count}) have identical price (#{top_price.price})"}

            # Good diversity
            true ->
              # Calculate Shannon entropy for price diversity
              diversity_score = calculate_price_entropy(price_distribution, paid_event_count)
              {unique_prices, diversity_score, nil}
          end

        true ->
          {unique_prices, 100, nil}
      end
    end
  end

  # Calculate Shannon entropy for price distribution
  # Similar to category entropy but for prices
  defp calculate_price_entropy(distribution, total_events) do
    if total_events == 0 or Enum.empty?(distribution) do
      100
    else
      # Calculate Shannon entropy: H = -Σ(p_i * log2(p_i))
      entropy =
        distribution
        |> Enum.reduce(0, fn price_data, acc ->
          p = price_data.count / total_events

          if p > 0 do
            acc - p * :math.log2(p)
          else
            acc
          end
        end)

      # Normalize to 0-100 scale
      # Maximum entropy is log2(number of unique prices)
      max_entropy = :math.log2(length(distribution))

      if max_entropy > 0 do
        round(entropy / max_entropy * 100)
      else
        100
      end
    end
  end

  # Calculate description quality score.
  #
  # Measures description richness based on character length across all languages:
  # - Missing: No description in any language (0 points)
  # - Too short (<50 chars): Poor quality, lacks context (25 points)
  # - Adequate (50-200 chars): Good quality, sufficient detail (75 points)
  # - Detailed (>200 chars): Excellent quality, comprehensive (100 points)
  #
  # Analyzes all languages in description_translations and uses best score.
  defp calculate_description_quality(source_id) do
    query =
      from(pes in PublicEventSource,
        where: pes.source_id == ^source_id,
        select: %{
          total: count(pes.id),
          # Has any description
          has_description:
            fragment(
              """
              COUNT(CASE
                WHEN ? IS NOT NULL
                AND jsonb_typeof(?) = 'object'
                AND (SELECT COUNT(*) FROM jsonb_object_keys(?)) > 0
                THEN 1
              END)
              """,
              pes.description_translations,
              pes.description_translations,
              pes.description_translations
            ),
          # Short descriptions (<50 chars)
          short_descriptions:
            fragment(
              """
              COUNT(CASE
                WHEN ? IS NOT NULL
                AND jsonb_typeof(?) = 'object'
                AND (
                  SELECT MAX(LENGTH(value::text))
                  FROM jsonb_each_text(?)
                ) < 50
                THEN 1
              END)
              """,
              pes.description_translations,
              pes.description_translations,
              pes.description_translations
            ),
          # Adequate descriptions (50-200 chars)
          adequate_descriptions:
            fragment(
              """
              COUNT(CASE
                WHEN ? IS NOT NULL
                AND jsonb_typeof(?) = 'object'
                AND (
                  SELECT MAX(LENGTH(value::text))
                  FROM jsonb_each_text(?)
                ) BETWEEN 50 AND 200
                THEN 1
              END)
              """,
              pes.description_translations,
              pes.description_translations,
              pes.description_translations
            ),
          # Detailed descriptions (>200 chars)
          detailed_descriptions:
            fragment(
              """
              COUNT(CASE
                WHEN ? IS NOT NULL
                AND jsonb_typeof(?) = 'object'
                AND (
                  SELECT MAX(LENGTH(value::text))
                  FROM jsonb_each_text(?)
                ) > 200
                THEN 1
              END)
              """,
              pes.description_translations,
              pes.description_translations,
              pes.description_translations
            ),
          # Average max length across all events
          avg_max_length:
            fragment(
              """
              AVG(
                CASE
                  WHEN ? IS NOT NULL
                  AND jsonb_typeof(?) = 'object'
                  THEN (
                    SELECT MAX(LENGTH(value::text))
                    FROM jsonb_each_text(?)
                  )
                  ELSE 0
                END
              )
              """,
              pes.description_translations,
              pes.description_translations,
              pes.description_translations
            )
        }
      )

    stats = Repo.one(query)

    if stats.total == 0 do
      %{
        description_quality: 100,
        total_events: 0,
        has_description: 0,
        short_descriptions: 0,
        adequate_descriptions: 0,
        detailed_descriptions: 0,
        avg_length: 0
      }
    else
      # Calculate weighted quality score
      # Missing: 0 points, Short: 25 points, Adequate: 75 points, Detailed: 100 points
      missing = stats.total - stats.has_description

      total_score =
        missing * 0 +
          stats.short_descriptions * 25 +
          stats.adequate_descriptions * 75 +
          stats.detailed_descriptions * 100

      description_quality = round(total_score / stats.total)

      avg_length =
        case stats.avg_max_length do
          nil -> 0
          %Decimal{} = decimal -> decimal |> Decimal.round(0) |> Decimal.to_integer()
          value when is_float(value) -> round(value)
          value when is_integer(value) -> value
          _ -> 0
        end

      %{
        description_quality: description_quality,
        total_events: stats.total,
        has_description: stats.has_description,
        short_descriptions: stats.short_descriptions,
        adequate_descriptions: stats.adequate_descriptions,
        detailed_descriptions: stats.detailed_descriptions,
        avg_length: avg_length
      }
    end
  end

  # Calculate performer data completeness.
  #
  # Measures how well performer/artist information is populated:
  # - Events with performers vs without (checks both performers table AND metadata)
  # - Single vs multiple performers
  # - Average performers per event
  #
  # Performer data is crucial for music events, theater, and performances.
  #
  # Phase 2 Update: Now checks BOTH:
  # 1. Performers table (public_event_performers) - traditional approach
  # 2. Metadata field (pes.metadata["quizmaster"]) - hybrid approach used by Geeks Who Drink
  defp calculate_performer_completeness(source_id) do
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        left_join: pep in "public_event_performers",
        on: pep.event_id == e.id,
        where: pes.source_id == ^source_id,
        group_by: [e.id, pes.metadata],
        select: %{
          event_id: e.id,
          # Count performers from performers table
          table_performer_count: count(pep.performer_id),
          # Check if metadata contains quizmaster (Geeks Who Drink pattern)
          # Uses jsonb_exists() to check if 'quizmaster' key exists in metadata
          has_metadata_performer:
            fragment(
              "CASE WHEN jsonb_exists(?, 'quizmaster') THEN 1 ELSE 0 END",
              pes.metadata
            )
        }
      )

    performer_data = Repo.all(query)
    total_events = length(performer_data)

    if total_events == 0 do
      %{
        performer_completeness: 100,
        total_events: 0,
        events_with_performers: 0,
        events_single_performer: 0,
        events_multiple_performers: 0,
        total_performers: 0,
        avg_performers_per_event: 0.0
      }
    else
      # Calculate metrics combining both performer sources
      # Total performer count = table performers + metadata performers
      performer_data_with_total =
        Enum.map(performer_data, fn d ->
          Map.put(d, :total_performer_count, d.table_performer_count + d.has_metadata_performer)
        end)

      events_with_performers =
        Enum.count(performer_data_with_total, fn d -> d.total_performer_count > 0 end)

      events_single = Enum.count(performer_data_with_total, fn d -> d.total_performer_count == 1 end)

      events_multiple =
        Enum.count(performer_data_with_total, fn d -> d.total_performer_count > 1 end)

      total_performers =
        Enum.reduce(performer_data_with_total, 0, fn d, acc -> acc + d.total_performer_count end)

      avg_performers =
        if events_with_performers > 0 do
          Float.round(total_performers / events_with_performers, 1)
        else
          0.0
        end

      # Completeness = % of events with at least one performer (from either source)
      performer_completeness = round(events_with_performers / total_events * 100)

      %{
        performer_completeness: performer_completeness,
        total_events: total_events,
        events_with_performers: events_with_performers,
        events_single_performer: events_single,
        events_multiple_performers: events_multiple,
        total_performers: total_performers,
        avg_performers_per_event: avg_performers
      }
    end
  end

  # Calculate occurrence richness and validity.
  #
  # Measures both richness and structural validity of occurrence data:
  #
  # Richness metrics:
  # - Events with occurrences vs without
  # - Single vs multiple dates
  # - Average dates per event
  # - Distribution by occurrence type (explicit, pattern, exhibition, recurring)
  #
  # Validation metrics:
  # - Pattern events missing required 'pattern' field (recurrence rules)
  # - Explicit events with only 1 date (may be miscategorized)
  # - Exhibition events with only 1 date (should have ranges)
  # - Overall structural validity score
  #
  # Occurrence data is crucial for event scheduling and user experience.
  defp calculate_occurrence_richness(source_id) do
    # Get occurrence data per event
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        where: pes.source_id == ^source_id,
        select: %{
          event_id: e.id,
          occurrences: e.occurrences
        }
      )

    occurrence_data = Repo.all(query)
    total_events = length(occurrence_data)

    if total_events == 0 do
      %{
        occurrence_richness: 100,
        total_events: 0,
        events_with_occurrences: 0,
        events_without_occurrences: 0,
        events_single_date: 0,
        events_multiple_dates: 0,
        avg_dates_per_event: 0.0,
        type_distribution: %{},
        validation_issues: %{
          pattern_missing_dates: 0,
          explicit_single_date: 0,
          exhibition_single_date: 0,
          total_validity_issues: 0
        },
        validity_score: 100
      }
    else
      # Analyze each event's occurrence data using reduce
      initial_state = %{
        events_with_occurrences: 0,
        events_without_occurrences: 0,
        events_single_date: 0,
        events_multiple_dates: 0,
        total_dates: 0,
        type_counts: %{},
        pattern_missing_dates: 0,
        explicit_single_date: 0,
        exhibition_single_date: 0
      }

      stats =
        Enum.reduce(occurrence_data, initial_state, fn event, acc ->
          case event.occurrences do
            nil ->
              %{acc | events_without_occurrences: acc.events_without_occurrences + 1}

            %{"type" => type, "dates" => dates} when is_list(dates) ->
              date_count = length(dates)

              acc
              |> Map.update!(:events_with_occurrences, &(&1 + 1))
              |> Map.update!(:total_dates, &(&1 + date_count))
              |> then(fn acc ->
                # Special handling for exhibition events: single-date arrays with end_date ranges
                # should be treated as rich data (date ranges), not single dates
                if date_count == 1 do
                  if type == "exhibition" do
                    # Check if this is a proper date range
                    has_end_date =
                      case List.first(dates) do
                        %{"end_date" => end_date} when not is_nil(end_date) -> true
                        _ -> false
                      end

                    if has_end_date do
                      # Exhibition with date range: treat as "multiple dates" for richness scoring
                      Map.update!(acc, :events_multiple_dates, &(&1 + 1))
                    else
                      # Invalid exhibition: missing end_date
                      acc
                      |> Map.update!(:events_single_date, &(&1 + 1))
                      |> Map.update!(:exhibition_single_date, &(&1 + 1))
                    end
                  else
                    # Explicit or other types: single date is genuinely single
                    acc
                    |> Map.update!(:events_single_date, &(&1 + 1))
                    |> then(fn acc ->
                      if type == "explicit",
                        do: Map.update!(acc, :explicit_single_date, &(&1 + 1)),
                        else: acc
                    end)
                  end
                else
                  # Multiple dates in array
                  Map.update!(acc, :events_multiple_dates, &(&1 + 1))
                end
              end)
              |> Map.update!(:type_counts, &Map.update(&1, type, 1, fn count -> count + 1 end))

            %{"type" => "pattern", "pattern" => pattern} when is_map(pattern) ->
              # Pattern events with recurrence rules are valid (no dates array needed)
              acc
              |> Map.update!(:events_with_occurrences, &(&1 + 1))
              |> Map.update!(
                :type_counts,
                &Map.update(&1, "pattern", 1, fn count -> count + 1 end)
              )

            %{"type" => type} ->
              # Has type but missing required field - actual validation issue
              # Pattern events need "pattern" field, other types need "dates" array
              acc
              |> Map.update!(:events_with_occurrences, &(&1 + 1))
              |> Map.update!(:type_counts, &Map.update(&1, type, 1, fn count -> count + 1 end))
              |> then(fn acc ->
                if type == "pattern",
                  do: Map.update!(acc, :pattern_missing_dates, &(&1 + 1)),
                  else: acc
              end)

            _ ->
              # Invalid structure
              %{acc | events_without_occurrences: acc.events_without_occurrences + 1}
          end
        end)

      # Calculate averages
      avg_dates =
        if stats.events_with_occurrences > 0 do
          Float.round(stats.total_dates / stats.events_with_occurrences, 1)
        else
          0.0
        end

      # Calculate richness score (adaptive weighting based on source type)
      # Base components:
      # - Has occurrences: 50%
      # - Multiple dates/ranges: 30%
      # - Type diversity OR validity: 20% (adaptive)
      has_occurrence_score =
        if total_events > 0,
          do: stats.events_with_occurrences / total_events * 100,
          else: 100

      multiple_date_score =
        if stats.events_with_occurrences > 0,
          do: stats.events_multiple_dates / stats.events_with_occurrences * 100,
          else: 100

      # Calculate validity score for the diversity/validity component
      total_validity_issues =
        stats.pattern_missing_dates + stats.explicit_single_date + stats.exhibition_single_date

      validity_score =
        if stats.events_with_occurrences > 0 do
          round(
            (stats.events_with_occurrences - total_validity_issues) /
              stats.events_with_occurrences * 100
          )
        else
          100
        end

      # Type diversity using Shannon entropy
      type_diversity_score =
        calculate_type_diversity(stats.type_counts, stats.events_with_occurrences)

      # Adaptive weighting: For specialized sources (low diversity), use validity instead
      # If type diversity < 50%, it indicates a specialized source (e.g., exhibition-only)
      # In this case, use validity score instead of penalizing for specialization
      diversity_component =
        if type_diversity_score < 50 do
          # Specialized source: use validity score (structural correctness matters more)
          validity_score
        else
          # Diverse source: use type diversity score
          type_diversity_score
        end

      occurrence_richness =
        round(
          has_occurrence_score * 0.5 +
            multiple_date_score * 0.3 +
            diversity_component * 0.2
        )

      %{
        occurrence_richness: occurrence_richness,
        total_events: total_events,
        events_with_occurrences: stats.events_with_occurrences,
        events_without_occurrences: stats.events_without_occurrences,
        events_single_date: stats.events_single_date,
        events_multiple_dates: stats.events_multiple_dates,
        avg_dates_per_event: avg_dates,
        type_distribution: stats.type_counts,
        validation_issues: %{
          pattern_missing_dates: stats.pattern_missing_dates,
          explicit_single_date: stats.explicit_single_date,
          exhibition_single_date: stats.exhibition_single_date,
          total_validity_issues: total_validity_issues
        },
        validity_score: validity_score
      }
    end
  end

  # Calculate time quality for occurrence dates.
  #
  # Detects suspicious time patterns that indicate parsing failures:
  # - High % of events at midnight (00:00) → likely missing time parsing
  # - High % of events at same time (>80%) → likely hardcoded default
  # - Low time diversity → limited time variety
  #
  # Time quality is crucial for event scheduling and user experience.
  defp calculate_time_quality(source_id) do
    # Get occurrence data per event
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        where: pes.source_id == ^source_id,
        where: not is_nil(e.occurrences),
        where: fragment("jsonb_typeof(?) = 'object'", e.occurrences),
        select: %{
          event_id: e.id,
          occurrences: e.occurrences
        }
      )

    occurrence_data = Repo.all(query)
    total_events = length(occurrence_data)

    if total_events == 0 do
      %{
        time_quality: 100,
        total_occurrences: 0,
        midnight_count: 0,
        midnight_percentage: 0,
        most_common_time: nil,
        most_common_time_count: 0,
        same_time_percentage: 0,
        hour_distribution: %{},
        time_diversity_score: 100
      }
    else
      # Extract all times from occurrence dates AND patterns
      times =
        occurrence_data
        |> Enum.flat_map(fn event ->
          case event.occurrences do
            # Explicit occurrences with dates array (movies, one-time events)
            %{"dates" => dates} when is_list(dates) ->
              Enum.map(dates, fn date_obj ->
                extract_time_from_date(date_obj)
              end)

            # Pattern occurrences (recurring events like trivia nights)
            %{"pattern" => %{"time" => time_str}} when is_binary(time_str) ->
              # Extract single time from pattern
              [parse_time_to_hour(time_str)]

            _ ->
              []
          end
        end)
        |> Enum.reject(&is_nil/1)

      if Enum.empty?(times) do
        # CRITICAL: Return 0% quality when no data analyzed (not 100%)
        # This prevents false positives where unsupported data structures
        # appear as "perfect quality" when they're actually not analyzed
        %{
          time_quality: 0,
          total_occurrences: 0,
          midnight_count: 0,
          midnight_percentage: 0,
          most_common_time: nil,
          most_common_time_count: 0,
          same_time_percentage: 0,
          hour_distribution: %{},
          time_diversity_score: 0
        }
      else
        analyze_time_quality(times)
      end
    end
  end

  # Extract time (hour) from a date object in occurrences
  defp extract_time_from_date(date_obj) when is_map(date_obj) do
    cond do
      # Check for "time" field first (e.g., Warsaw events use {"date": "2025-11-11", "time": "18:00"})
      Map.has_key?(date_obj, "time") and is_binary(date_obj["time"]) ->
        parse_time_to_hour(date_obj["time"])

      # Check for "start_time" field
      Map.has_key?(date_obj, "start_time") and is_binary(date_obj["start_time"]) ->
        parse_time_to_hour(date_obj["start_time"])

      # Check for "date" field that might contain datetime
      Map.has_key?(date_obj, "date") and is_binary(date_obj["date"]) ->
        # Only parse if it contains time info (has "T" for ISO datetime)
        if String.contains?(date_obj["date"], "T") do
          parse_time_to_hour(date_obj["date"])
        else
          # Date only, no time info - default to midnight
          0
        end

      # No time info found
      true ->
        0
    end
  end

  defp extract_time_from_date(_), do: nil

  # Parse time string to hour (0-23)
  defp parse_time_to_hour(time_str) when is_binary(time_str) do
    cond do
      # ISO 8601 datetime: "2025-11-05T18:00:00Z"
      String.contains?(time_str, "T") ->
        case DateTime.from_iso8601(time_str) do
          {:ok, dt, _} -> dt.hour
          _ -> 0
        end

      # Time only: "18:00" or "18:00:00"
      String.contains?(time_str, ":") ->
        case Time.from_iso8601(time_str) do
          {:ok, time} ->
            time.hour

          _ ->
            # Try parsing just HH:MM
            case String.split(time_str, ":") do
              [hour_str | _] ->
                case Integer.parse(hour_str) do
                  {hour, _} when hour >= 0 and hour <= 23 -> hour
                  _ -> 0
                end

              _ ->
                0
            end
        end

      # No time info, default to midnight
      true ->
        0
    end
  end

  defp parse_time_to_hour(_), do: 0

  # Analyze time distribution and calculate quality metrics
  defp analyze_time_quality(times) do
    total_occurrences = length(times)

    # Count occurrences by hour (0-23)
    hour_distribution =
      times
      |> Enum.frequencies()
      |> Map.new(fn {hour, count} -> {hour, count} end)

    # Calculate midnight count and percentage
    midnight_count = Map.get(hour_distribution, 0, 0)
    midnight_percentage = Float.round(midnight_count / total_occurrences * 100, 1)

    # Find most common time
    {most_common_hour, most_common_count} =
      hour_distribution
      |> Enum.max_by(fn {_hour, count} -> count end, fn -> {nil, 0} end)

    most_common_time = if most_common_hour, do: format_hour(most_common_hour), else: nil
    same_time_percentage = Float.round(most_common_count / total_occurrences * 100, 1)

    # Calculate time diversity using Shannon entropy
    time_diversity_score = calculate_time_diversity(hour_distribution, total_occurrences)

    # Calculate overall time quality score
    # Weighted components:
    # - midnight_penalty: High % at 00:00 suggests parsing failure (40%)
    # - diversity_score: Low diversity suggests hardcoded times (40%)
    # - same_time_penalty: >80% at same time is suspicious (20%)

    midnight_penalty =
      cond do
        midnight_percentage > 50 -> 0
        midnight_percentage > 30 -> 50
        true -> 100
      end

    same_time_penalty =
      cond do
        same_time_percentage > 90 -> 0
        same_time_percentage > 80 -> 25
        same_time_percentage > 70 -> 50
        true -> 100
      end

    time_quality =
      round(
        midnight_penalty * 0.4 +
          time_diversity_score * 0.4 +
          same_time_penalty * 0.2
      )

    %{
      time_quality: time_quality,
      total_occurrences: total_occurrences,
      midnight_count: midnight_count,
      midnight_percentage: midnight_percentage,
      most_common_time: most_common_time,
      most_common_time_count: most_common_count,
      same_time_percentage: same_time_percentage,
      hour_distribution: hour_distribution,
      time_diversity_score: time_diversity_score
    }
  end

  # Calculate time diversity using Shannon entropy
  defp calculate_time_diversity(hour_distribution, total_occurrences) do
    if total_occurrences == 0 or map_size(hour_distribution) == 0 do
      100
    else
      # Calculate Shannon entropy: H = -Σ(p_i * log2(p_i))
      entropy =
        hour_distribution
        |> Enum.reduce(0, fn {_hour, count}, acc ->
          p = count / total_occurrences

          if p > 0 do
            acc - p * :math.log2(p)
          else
            acc
          end
        end)

      # Normalize to 0-100 scale
      # Maximum entropy is log2(24) since we have 24 hours
      max_entropy = :math.log2(24)

      if max_entropy > 0 do
        round(entropy / max_entropy * 100)
      else
        100
      end
    end
  end

  # Format hour (0-23) to HH:MM string
  defp format_hour(hour) when is_integer(hour) and hour >= 0 and hour <= 23 do
    hour_str = hour |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{hour_str}:00"
  end

  defp format_hour(_), do: nil

  # Calculate type diversity using Shannon entropy
  defp calculate_type_diversity(type_counts, total_events) do
    if total_events == 0 or map_size(type_counts) == 0 do
      100
    else
      # Calculate Shannon entropy: H = -Σ(p_i * log2(p_i))
      entropy =
        type_counts
        |> Enum.reduce(0, fn {_type, count}, acc ->
          p = count / total_events

          if p > 0 do
            acc - p * :math.log2(p)
          else
            acc
          end
        end)

      # Normalize to 0-100 scale
      # Maximum entropy is log2(4) since we have 4 occurrence types
      max_entropy = :math.log2(4)

      if max_entropy > 0 do
        round(entropy / max_entropy * 100)
      else
        100
      end
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
         price_completeness,
         description_quality,
         performer_completeness,
         occurrence_richness,
         translation_completeness
       ) do
    if translation_completeness do
      # 9 dimensions (with translations)
      # Weights: venue 16%, image 15%, category 15%, specificity 15%,
      # occurrence 13%, price 10%, description 8%, performer 6%, translation 2%
      (venue_completeness * 0.16 +
         image_completeness * 0.15 +
         category_completeness * 0.15 +
         category_specificity * 0.15 +
         occurrence_richness * 0.13 +
         price_completeness * 0.10 +
         description_quality * 0.08 +
         performer_completeness * 0.06 +
         translation_completeness * 0.02)
      |> round()
    else
      # 8 dimensions (without translations)
      # Weights: venue 20%, image 18%, category 16%, specificity 16%,
      # occurrence 14%, price 10%, description 6%, performer 0%
      (venue_completeness * 0.20 +
         image_completeness * 0.18 +
         category_completeness * 0.16 +
         category_specificity * 0.16 +
         occurrence_richness * 0.14 +
         price_completeness * 0.10 +
         description_quality * 0.06 +
         performer_completeness * 0.00)
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
