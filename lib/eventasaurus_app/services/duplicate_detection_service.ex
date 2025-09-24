defmodule EventasaurusApp.Services.DuplicateDetectionService do
  @moduledoc """
  Service for detecting duplicate poll options using fuzzy string matching
  and external API identifiers.
  """

  alias EventasaurusApp.Events.PollOption

  @default_similarity_threshold 0.8

  @doc """
  Analyzes a new poll option suggestion for potential duplicates.

  Returns:
  - `{:ok, :no_duplicates}` - No duplicates found
  - `{:ok, {:exact_duplicate, option}}` - Exact duplicate found (external_id match)
  - `{:ok, {:similar_options, options}}` - Similar options found (fuzzy match)
  - `{:error, reason}` - Error occurred
  """
  def analyze_for_duplicates(poll_id, title, external_id \\ nil, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, @default_similarity_threshold)

    with {:ok, existing_options} <- get_poll_options(poll_id) do
      # First check for exact external_id match
      case check_external_id_duplicate(existing_options, external_id) do
        {:found, option} ->
          {:ok, {:exact_duplicate, option}}

        :not_found ->
          # Then check for fuzzy title matches
          similar_options = find_similar_titles(existing_options, title, threshold)

          case similar_options do
            [] -> {:ok, :no_duplicates}
            options -> {:ok, {:similar_options, options}}
          end
      end
    end
  end

  @doc """
  Batch analyzes multiple options for potential duplicates within a poll.
  Useful for finding duplicates within existing poll options.
  """
  def batch_analyze_duplicates(poll_id, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, @default_similarity_threshold)

    with {:ok, options} <- get_poll_options(poll_id) do
      duplicate_groups = find_duplicate_groups(options, threshold)
      {:ok, duplicate_groups}
    end
  end

  @doc """
  Calculates similarity score between two poll option titles.
  Returns a float between 0.0 (no similarity) and 1.0 (identical).
  """
  def similarity_score(title1, title2) when is_binary(title1) and is_binary(title2) do
    normalized1 = normalize_title(title1)
    normalized2 = normalize_title(title2)

    # Use Jaro-Winkler distance for better fuzzy matching
    jaro_winkler_similarity(normalized1, normalized2)
  end

  @doc """
  Gets suggested merge data for combining similar options.
  """
  def suggest_merge(option1, option2) do
    %{
      primary_option: select_primary_option(option1, option2),
      secondary_option: select_secondary_option(option1, option2),
      suggested_title: suggest_best_title(option1, option2),
      suggested_description: suggest_best_description(option1, option2),
      merge_strategy: determine_merge_strategy(option1, option2)
    }
  end

  # Private helper functions

  defp get_poll_options(poll_id) do
    try do
      # Get poll first, then get options
      poll = EventasaurusApp.Events.get_poll!(poll_id)
      options = EventasaurusApp.Events.list_poll_options(poll)
      {:ok, options}
    rescue
      error -> {:error, error}
    end
  end

  defp check_external_id_duplicate(_options, nil), do: :not_found
  defp check_external_id_duplicate(_options, ""), do: :not_found

  defp check_external_id_duplicate(options, external_id) do
    case Enum.find(options, fn option -> option.external_id == external_id end) do
      nil -> :not_found
      option -> {:found, option}
    end
  end

  defp find_similar_titles(options, title, threshold) do
    options
    |> Enum.map(fn option ->
      score = similarity_score(option.title, title)
      {option, score}
    end)
    |> Enum.filter(fn {_option, score} -> score >= threshold end)
    |> Enum.sort_by(fn {_option, score} -> score end, :desc)
    |> Enum.map(fn {option, score} ->
      %{option: option, similarity_score: score}
    end)
  end

  defp find_duplicate_groups(options, threshold) do
    options
    |> Enum.with_index()
    |> Enum.reduce([], fn {option, index}, acc ->
      # Compare with remaining options to avoid duplicates
      remaining_options = Enum.drop(options, index + 1)

      similar = find_similar_titles(remaining_options, option.title, threshold)

      case similar do
        [] ->
          acc

        matches ->
          group = [%{option: option, similarity_score: 1.0} | matches]
          [group | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_title(title) do
    title
    |> String.downcase()
    |> String.trim()
    # Remove special characters
    |> String.replace(~r/[^\w\s]/, "")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
  end

  # Simplified Jaro-Winkler implementation
  defp jaro_winkler_similarity(str1, str2) do
    len1 = String.length(str1)
    len2 = String.length(str2)

    # Handle edge cases
    cond do
      len1 == 0 and len2 == 0 -> 1.0
      len1 == 0 or len2 == 0 -> 0.0
      str1 == str2 -> 1.0
      true -> calculate_jaro_similarity(str1, str2, len1, len2)
    end
  end

  defp calculate_jaro_similarity(str1, str2, len1, len2) do
    # Simple Jaro distance implementation
    match_window = max(len1, len2) |> div(2) |> max(1) |> Kernel.-(1)

    chars1 = String.graphemes(str1)
    chars2 = String.graphemes(str2)

    {matches1, matches2} = find_matches(chars1, chars2, match_window)

    if length(matches1) == 0 do
      0.0
    else
      transpositions = count_transpositions(matches1, matches2)
      matches = length(matches1)

      jaro = (matches / len1 + matches / len2 + (matches - transpositions) / matches) / 3

      # Add Winkler prefix bonus (up to 0.1)
      prefix_length = common_prefix_length(str1, str2, 4)
      jaro + prefix_length * 0.1 * (1 - jaro)
    end
  end

  defp find_matches(chars1, chars2, match_window) do
    len2 = length(chars2)

    {matches1, matches2, _} =
      chars1
      |> Enum.with_index()
      |> Enum.reduce({[], [], chars2}, fn {char1, i},
                                          {acc_matches1, acc_matches2, remaining_chars2} ->
        start_pos = max(0, i - match_window)
        end_pos = min(len2 - 1, i + match_window)

        case find_and_remove_match(char1, remaining_chars2, start_pos, end_pos, 0) do
          {:found, char, new_remaining} ->
            {[char1 | acc_matches1], [char | acc_matches2], new_remaining}

          :not_found ->
            {acc_matches1, acc_matches2, remaining_chars2}
        end
      end)

    {Enum.reverse(matches1), Enum.reverse(matches2)}
  end

  defp find_and_remove_match(_char, [], _start, _end, _current_pos), do: :not_found

  defp find_and_remove_match(char, [h | t], start_pos, end_pos, current_pos) do
    cond do
      current_pos > end_pos ->
        :not_found

      current_pos < start_pos ->
        find_and_remove_match(char, t, start_pos, end_pos, current_pos + 1)

      char == h ->
        {:found, h, t}

      true ->
        case find_and_remove_match(char, t, start_pos, end_pos, current_pos + 1) do
          {:found, found_char, remaining} -> {:found, found_char, [h | remaining]}
          :not_found -> :not_found
        end
    end
  end

  defp count_transpositions(matches1, matches2) do
    matches1
    |> Enum.zip(matches2)
    |> Enum.count(fn {c1, c2} -> c1 != c2 end)
    |> div(2)
  end

  defp common_prefix_length(str1, str2, max_length) do
    chars1 = String.graphemes(str1)
    chars2 = String.graphemes(str2)

    chars1
    |> Enum.zip(chars2)
    |> Enum.take(max_length)
    |> Enum.take_while(fn {c1, c2} -> c1 == c2 end)
    |> length()
  end

  # Merge suggestion helpers

  defp select_primary_option(option1, option2) do
    cond do
      has_more_data?(option1, option2) -> option1
      option1.inserted_at <= option2.inserted_at -> option1
      true -> option2
    end
  end

  defp select_secondary_option(option1, option2) do
    if select_primary_option(option1, option2) == option1, do: option2, else: option1
  end

  defp suggest_best_title(option1, option2) do
    # Prefer the longer, more descriptive title
    if String.length(option1.title) >= String.length(option2.title) do
      option1.title
    else
      option2.title
    end
  end

  defp suggest_best_description(option1, option2) do
    case {option1.description, option2.description} do
      {nil, desc2} ->
        desc2

      {desc1, nil} ->
        desc1

      {"", desc2} ->
        desc2

      {desc1, ""} ->
        desc1

      {desc1, desc2} ->
        if String.length(desc1) >= String.length(desc2), do: desc1, else: desc2
    end
  end

  defp determine_merge_strategy(option1, option2) do
    cond do
      option1.external_id && option2.external_id && option1.external_id == option2.external_id ->
        :identical_external_data

      has_external_data?(option1) && !has_external_data?(option2) ->
        :keep_external_data_from_first

      has_external_data?(option2) && !has_external_data?(option1) ->
        :keep_external_data_from_second

      has_external_data?(option1) && has_external_data?(option2) ->
        :manual_review_required

      true ->
        :simple_merge
    end
  end

  defp has_more_data?(option1, option2) do
    score1 = data_richness_score(option1)
    score2 = data_richness_score(option2)
    score1 > score2
  end

  defp data_richness_score(option) do
    score = 0

    score =
      if option.description && String.trim(option.description) != "", do: score + 1, else: score

    score = if option.image_url && String.trim(option.image_url) != "", do: score + 1, else: score
    score = if has_external_data?(option), do: score + 2, else: score

    score =
      if option.external_id && String.trim(option.external_id) != "", do: score + 1, else: score

    score
  end

  defp has_external_data?(%PollOption{external_data: nil}), do: false
  defp has_external_data?(%PollOption{external_data: data}) when map_size(data) == 0, do: false
  defp has_external_data?(%PollOption{external_data: _}), do: true
end
