defmodule EventasaurusDiscovery.Validation.VenueNameValidator do
  @moduledoc """
  Validates venue names by comparing scraped names against geocoding provider names.

  Uses similarity scoring instead of pattern matching for robustness. This approach:
  - Works universally for any bad pattern (UI text, numbers, symbols, any language)
  - Is language agnostic (works for Polish, English, French, etc.)
  - Requires no maintenance (no regex patterns to update)
  - Uses trusted sources (geocoding providers are authoritative)
  - Is measurable (similarity score gives confidence level)
  - Uses data already in metadata (no API calls needed)

  ## Examples

      # Good match - names similar
      iex> metadata = %{"geocoding_metadata" => %{"raw_response" => %{"title" => "La Lucy"}}}
      iex> match?({:ok, :high_similarity, _score}, VenueNameValidator.validate_against_geocoded("La Lucy Cafe", metadata))
      true

      # Bad match - scraped UI element vs real venue name
      iex> metadata = %{"geocoding_metadata" => %{"raw_response" => %{"title" => "Central Park"}}}
      iex> match?({:error, :low_similarity, _score}, VenueNameValidator.validate_against_geocoded("00000", metadata))
      true
  """

  # Similarity thresholds
  # Names match well (valid venue name)
  @high_similarity 0.7
  # Names very different (likely UI element or bad scrape)
  @low_similarity 0.3

  @doc """
  Validates scraped venue name against geocoded name from metadata.

  Returns:
  - `{:ok, :high_similarity, score}` - Names match well, use scraped name
  - `{:warning, :moderate_similarity, score}` - Names differ somewhat, prefer geocoded
  - `{:error, :low_similarity, score}` - Names very different, use geocoded name
  - `{:error, :no_geocoded_name}` - No trusted name to compare against

  ## Examples

      iex> metadata = %{"geocoding_metadata" => %{"raw_response" => %{"title" => "Madison Square Garden"}}}
      iex> match?({:warning, :moderate_similarity, _score}, VenueNameValidator.validate_against_geocoded("MSG", metadata))
      true

      iex> metadata = %{"geocoding_metadata" => %{"raw_response" => %{"title" => "Madison Square Garden"}}}
      iex> match?({:error, :low_similarity, _score}, VenueNameValidator.validate_against_geocoded("00000", metadata))
      true
  """
  def validate_against_geocoded(scraped_name, metadata) when is_binary(scraped_name) do
    case extract_geocoded_name(metadata) do
      nil ->
        {:error, :no_geocoded_name}

      geocoded_name ->
        similarity = calculate_similarity(scraped_name, geocoded_name)

        cond do
          similarity >= @high_similarity ->
            {:ok, :high_similarity, similarity}

          similarity >= @low_similarity ->
            {:warning, :moderate_similarity, similarity}

          true ->
            {:error, :low_similarity, similarity}
        end
    end
  end

  @doc """
  Extracts venue name from geocoding metadata.

  Checks multiple providers and their specific response formats:
  - HERE: `raw_response.title` (best - has actual business names)
  - Google Places: `raw_response.name`
  - Foursquare: `raw_response.name`
  - Other providers: May only have street names or no venue names

  ## Examples

      iex> metadata = %{"geocoding_metadata" => %{"raw_response" => %{"title" => "La Lucy"}}}
      iex> VenueNameValidator.extract_geocoded_name(metadata)
      "La Lucy"

      iex> metadata = %{"geocoding_metadata" => %{"provider" => "mapbox"}}
      iex> VenueNameValidator.extract_geocoded_name(metadata)
      nil
  """
  def extract_geocoded_name(metadata) when is_map(metadata) do
    geocoding_data = metadata["geocoding_metadata"] || metadata[:geocoding_metadata]

    if geocoding_data do
      raw_response =
        case geocoding_data["raw_response"] || geocoding_data[:raw_response] do
          value when is_map(value) -> value
          _ -> %{}
        end

      title =
        Map.get(raw_response, "title") ||
          Map.get(raw_response, :title)

      name =
        Map.get(raw_response, "name") ||
          Map.get(raw_response, :name)

      cond do
        is_binary(title) and title != "" -> title
        is_binary(name) and name != "" -> name
        true -> nil
      end
    else
      nil
    end
  end

  def extract_geocoded_name(_), do: nil

  @doc """
  Calculates similarity between two venue names using Jaro distance.

  Returns score from 0.0 (completely different) to 1.0 (identical).
  Uses the same algorithm as VenueProcessor for GPS-based matching.

  ## Examples

      iex> similarity = VenueNameValidator.calculate_similarity("Madison Square Garden", "MSG")
      iex> similarity > 0.4 and similarity < 0.7
      true

      iex> similarity = VenueNameValidator.calculate_similarity("La Lucy", "La Lucy Cafe")
      iex> similarity > 0.8
      true

      iex> similarity = VenueNameValidator.calculate_similarity("00000", "Central Park")
      iex> similarity < 0.3
      true
  """
  def calculate_similarity(name1, name2) when is_binary(name1) and is_binary(name2) do
    # PostgreSQL boundary protection: clean UTF-8 before similarity calculation
    # (same as VenueProcessor to prevent jaro_distance crashes)
    clean_name1 = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name1)
    clean_name2 = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name2)

    # Normalize for better comparison (more aggressive than VenueProcessor)
    norm1 = normalize_for_comparison(clean_name1)
    norm2 = normalize_for_comparison(clean_name2)

    # Use Jaro distance (same algorithm as VenueProcessor uses for GPS matching)
    String.jaro_distance(norm1, norm2)
  end

  @doc """
  Determines which name to use based on validation result.

  Returns tuple with:
  - Chosen name
  - Reason for the choice
  - Similarity score (if applicable)

  ## Examples

      iex> metadata = %{"geocoding_metadata" => %{"raw_response" => %{"title" => "Central Park"}}}
      iex> match?({:ok, "Central Park", :geocoded_low_similarity, _score}, VenueNameValidator.choose_name("00000", metadata))
      true
  """
  def choose_name(scraped_name, metadata) do
    case validate_against_geocoded(scraped_name, metadata) do
      {:ok, :high_similarity, _score} ->
        # Names match well, use scraped (might be more specific)
        {:ok, scraped_name, :scraped_validated}

      {:warning, :moderate_similarity, score} ->
        # Moderate difference - prefer geocoded but log warning
        geocoded = extract_geocoded_name(metadata)
        {:ok, geocoded || scraped_name, :geocoded_moderate_diff, score}

      {:error, :low_similarity, score} ->
        # Very different - strongly prefer geocoded
        geocoded = extract_geocoded_name(metadata)
        {:ok, geocoded, :geocoded_low_similarity, score}

      {:error, :no_geocoded_name} ->
        # No comparison possible - use scraped and flag for review
        {:warning, scraped_name, :no_geocoded_name}
    end
  end

  # Private functions

  # Normalize names for comparison
  defp normalize_for_comparison(name) do
    name
    |> String.downcase()
    # Remove punctuation but keep Unicode letters and numbers
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
    |> String.trim()
  end
end
