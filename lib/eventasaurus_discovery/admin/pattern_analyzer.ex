defmodule EventasaurusDiscovery.Admin.PatternAnalyzer do
  @moduledoc """
  Analyzes patterns in uncategorized events to suggest category mappings.
  Extracts URL patterns, keywords, and venue type distributions.
  """

  @doc """
  Analyzes a list of events and extracts patterns for categorization.
  Returns a map with url_patterns, title_keywords, and venue_types.
  """
  def analyze_patterns(events) do
    %{
      url_patterns: extract_url_patterns(events),
      title_keywords: extract_title_keywords(events),
      venue_types: analyze_venue_types(events)
    }
  end

  @doc """
  Extracts URL path patterns from event source URLs.
  Returns list of {pattern, count, percentage, sample_events}.
  """
  def extract_url_patterns(events) do
    # Count total events with valid URLs for percentage calculation
    total_with_url =
      Enum.count(events, fn e ->
        case e.source_url do
          s when is_binary(s) -> String.trim(s) != ""
          _ -> false
        end
      end)

    events
    |> Enum.flat_map(fn event ->
      case extract_path_segments(event.source_url) do
        [] -> []
        segments -> segments
      end
    end)
    |> Enum.frequencies()
    |> Enum.map(fn {pattern, count} ->
      # Use events with URLs as denominator to avoid division by zero and get accurate percentage
      denominator = max(total_with_url, 1)
      percentage = Float.round(count / denominator * 100, 1)
      sample_events = get_sample_events_for_pattern(events, pattern, 3)

      %{
        pattern: pattern,
        count: count,
        percentage: percentage,
        sample_events: sample_events
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(10)
  end

  @doc """
  Extracts keywords from event titles.
  Returns list of {keyword, count, percentage, sample_events}.
  """
  def extract_title_keywords(events) do
    # French stop words to filter out
    stop_words = ~w[
      le la les de du des un une et ou à dans pour par avec sur
      au aux en ce cette ces son sa ses leur leurs qui que quoi
      dont où il elle ils elles nous vous mon ma mes ton ta tes
      son sa ses notre nos votre vos leur leurs plus moins très
      tout toute tous toutes même mêmes aussi bien encore enfin
      donc car mais
    ]

    # Count total events with valid titles for percentage calculation
    total_with_titles =
      Enum.count(events, fn e ->
        is_binary(e.title) and String.trim(e.title) != ""
      end)

    events
    |> Enum.flat_map(fn event ->
      case event.title do
        s when is_binary(s) ->
          s
          |> normalize_text()
          |> String.replace(~r/[^\p{L}\s]/u, " ")
          |> String.split()
          |> Enum.reject(&(&1 in stop_words or String.length(&1) < 3))
          # Count at most once per event to get event coverage, not word count
          |> MapSet.new()
          |> MapSet.to_list()

        _ ->
          []
      end
    end)
    |> Enum.frequencies()
    |> Enum.map(fn {keyword, count} ->
      # Use events with titles as denominator to avoid division by zero
      percentage = Float.round(count / max(total_with_titles, 1) * 100, 1)
      sample_events = get_sample_events_for_keyword(events, keyword, 3)

      %{
        keyword: keyword,
        count: count,
        percentage: percentage,
        sample_events: sample_events
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(15)
  end

  @doc """
  Analyzes venue type distribution.
  Returns list of {venue_type, count, percentage}.
  """
  def analyze_venue_types(events) do
    events
    |> Enum.map(& &1.venue_type)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.map(fn {venue_type, count} ->
      total_with_venue = Enum.count(events, &(&1.venue_type != nil))

      percentage =
        if total_with_venue > 0 do
          Float.round(count / total_with_venue * 100, 1)
        else
          0.0
        end

      %{
        venue_type: venue_type,
        count: count,
        percentage: percentage
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(10)
  end

  @doc """
  Generates suggested category mappings based on patterns.
  Returns list of suggestions with YAML snippets.
  """
  def generate_suggestions(patterns, available_categories) do
    url_suggestions = generate_url_suggestions(patterns.url_patterns, available_categories)

    keyword_suggestions =
      generate_keyword_suggestions(patterns.title_keywords, available_categories)

    (url_suggestions ++ keyword_suggestions)
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, suggestions} ->
      merge_suggestions(category, suggestions)
    end)
    |> Enum.sort_by(& &1.event_count, :desc)
  end

  # Private functions

  defp extract_path_segments(url) when is_binary(url) do
    uri = URI.parse(url)

    if uri.path do
      uri.path
      |> String.split("/", trim: true)
      |> Enum.map(&String.downcase/1)
      |> Enum.reject(&(&1 =~ ~r/^\d+$|^articles?$|^events?$/))
    else
      []
    end
  end

  defp extract_path_segments(_), do: []

  defp get_sample_events_for_pattern(events, pattern, limit) do
    events
    |> Enum.filter(fn event ->
      case event.source_url do
        nil -> false
        url -> String.contains?(String.downcase(url), pattern)
      end
    end)
    |> Enum.take(limit)
    |> Enum.map(&%{id: &1.id, title: &1.title})
  end

  defp get_sample_events_for_keyword(events, keyword, limit) do
    norm_kw = normalize_text(keyword)

    events
    |> Enum.filter(fn event ->
      case event.title do
        s when is_binary(s) -> String.contains?(normalize_text(s), norm_kw)
        _ -> false
      end
    end)
    |> Enum.take_random(limit)
    |> Enum.map(&%{id: &1.id, title: &1.title})
  end

  # Normalize text by removing accents/diacritics and lowercasing
  # This helps with French text matching (e.g., "éléphant" matches "elephant")
  defp normalize_text(s) when is_binary(s) do
    s
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
  end

  defp normalize_text(_), do: ""

  defp generate_url_suggestions(url_patterns, categories) do
    url_patterns
    |> Enum.flat_map(fn pattern_data ->
      match_pattern_to_category(pattern_data, categories, :url)
    end)
  end

  defp generate_keyword_suggestions(keywords, categories) do
    keywords
    |> Enum.flat_map(fn keyword_data ->
      match_pattern_to_category(keyword_data, categories, :keyword)
    end)
  end

  defp match_pattern_to_category(data, categories, type) do
    pattern_value = if type == :url, do: data.pattern, else: data.keyword

    # Pattern matching heuristics
    matches = [
      {~r/concert|music|band|dj|live/i, "concerts"},
      {~r/theatre|spectacle|piece|play/i, "theatre"},
      {~r/exposition|exhibit|gallery|musee|museum/i, "arts"},
      {~r/festival/i, "festivals"},
      {~r/film|cinema|movie|screening/i, "film"},
      {~r/sport|match|game/i, "sports"},
      {~r/comedy|humour|stand.?up/i, "comedy"},
      {~r/food|restaurant|gastronomie|cuisine/i, "food-drink"},
      {~r/nightlife|club|soiree|party/i, "nightlife"},
      {~r/family|enfant|kids|children/i, "family"},
      {~r/education|workshop|atelier|course/i, "education"},
      {~r/business|conference|networking/i, "business"},
      {~r/community|charity|volunteer/i, "community"},
      {~r/trivia|quiz/i, "trivia"}
    ]

    matches
    |> Enum.filter(fn {regex, _cat} -> Regex.match?(regex, pattern_value) end)
    |> Enum.map(fn {_regex, category_slug} ->
      category = Enum.find(categories, &(&1.slug == category_slug))

      if category do
        %{
          type: type,
          pattern: pattern_value,
          category: category.name,
          category_slug: category_slug,
          event_count: data.count,
          confidence: calculate_confidence(data, type),
          sample_events: data.sample_events
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp calculate_confidence(data, :url) when data.count >= 10, do: :high
  defp calculate_confidence(data, :url) when data.count >= 5, do: :medium
  defp calculate_confidence(_data, :url), do: :low

  defp calculate_confidence(data, :keyword) when data.count >= 15, do: :high
  defp calculate_confidence(data, :keyword) when data.count >= 8, do: :medium
  defp calculate_confidence(_data, :keyword), do: :low

  defp merge_suggestions(category, suggestions) do
    # Deduplicate patterns and keywords
    url_patterns =
      suggestions
      |> Enum.filter(&(&1.type == :url))
      |> Enum.map(& &1.pattern)
      |> Enum.uniq()

    keywords =
      suggestions
      |> Enum.filter(&(&1.type == :keyword))
      |> Enum.map(& &1.pattern)
      |> Enum.uniq()

    # Count unique events to avoid double-counting across suggestions
    total_events =
      suggestions
      |> Enum.flat_map(& &1.sample_events)
      |> Enum.uniq_by(& &1.id)
      |> length()

    avg_confidence = suggestions |> Enum.map(&confidence_to_num(&1.confidence)) |> Enum.sum()
    avg_confidence = div(avg_confidence, length(suggestions))

    category_slug = suggestions |> List.first() |> Map.get(:category_slug)

    yaml = generate_yaml_snippet(category_slug, url_patterns, keywords)

    %{
      category: category,
      category_slug: category_slug,
      url_patterns: url_patterns,
      keywords: keywords,
      event_count: total_events,
      confidence: num_to_confidence(avg_confidence),
      yaml: yaml,
      sample_events:
        suggestions |> Enum.flat_map(& &1.sample_events) |> Enum.uniq_by(& &1.id) |> Enum.take(3)
    }
  end

  defp confidence_to_num(:high), do: 3
  defp confidence_to_num(:medium), do: 2
  defp confidence_to_num(:low), do: 1

  defp num_to_confidence(n) when n >= 3, do: :high
  defp num_to_confidence(n) when n >= 2, do: :medium
  defp num_to_confidence(_), do: :low

  defp generate_yaml_snippet(category_slug, url_patterns, keywords) do
    # Handle empty sections properly to avoid invalid YAML
    url_block =
      case Enum.uniq(url_patterns) do
        [] ->
          "  url_patterns: []"

        ups ->
          "  url_patterns:\n" <>
            Enum.map_join(ups, "\n", fn p -> "    - " <> yaml_quote("/" <> p <> "/") end)
      end

    kw_block =
      case Enum.uniq(keywords) do
        [] ->
          "  keywords: []"

        ks ->
          "  keywords:\n" <>
            Enum.map_join(ks, "\n", fn k -> "    - " <> yaml_quote(k) end)
      end

    """
    #{category_slug}:
    #{url_block}
    #{kw_block}
    """
    |> String.trim()
  end

  # Properly escape quotes in YAML strings
  defp yaml_quote(s) when is_binary(s) do
    ~s("#{String.replace(s, ~S("), ~S(\\"))}")
  end
end
