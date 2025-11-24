defmodule EventasaurusDiscovery.Locations.VenueNameMatcher do
  @moduledoc """
  Sophisticated venue name matching using token-based similarity scoring.

  Handles cases like:
  - "Cinema City Bonarka" vs "Kraków - Bonarka" (should match - both at Bonarka)
  - "Cinema City Kazimierz" vs "Kraków - Galeria Kazimierz" (should match)
  - "Cinema City Kazimierz" vs "Nalej Se" (should NOT match - different venues)

  Uses a scoring system that combines:
  1. Token extraction (removes stop words, prefixes)
  2. Significant token matching
  3. Distance-weighted acceptance thresholds
  """

  require Logger

  # Common prefixes/stop words that don't indicate venue identity
  @stop_words ~w(
    krakow kraków krakau
    cinema city
    galeria gallery
    the
    at
    in
  )

  # Venue type suffixes that are descriptive but not identifying
  @venue_types ~w(
    arena stadium club hall theater theatre
    center centre venue stage room space
    bar lounge pub house
    muzeum museum
    teatr
  )

  @doc """
  Calculate similarity score between two venue names.
  Returns a score between 0.0 (completely different) and 1.0 (identical).
  """
  def similarity_score(name1, name2) when is_binary(name1) and is_binary(name2) do
    tokens1 = extract_significant_tokens(name1)
    tokens2 = extract_significant_tokens(name2)

    if Enum.empty?(tokens1) or Enum.empty?(tokens2) do
      0.0
    else
      # Calculate token overlap
      common_tokens = MapSet.intersection(MapSet.new(tokens1), MapSet.new(tokens2))
      total_tokens = MapSet.union(MapSet.new(tokens1), MapSet.new(tokens2))

      jaccard = MapSet.size(common_tokens) / MapSet.size(total_tokens)

      # Bonus for having ANY shared significant token (location identifier)
      has_shared_location = MapSet.size(common_tokens) > 0
      location_bonus = if has_shared_location, do: 0.2, else: 0.0

      # Calculate final score (cap at 1.0)
      min(jaccard + location_bonus, 1.0)
    end
  end

  def similarity_score(_, _), do: 0.0

  @doc """
  Check if two venue names should match based on name similarity and distance.

  Distance bands with required similarity:
  - 0-100m: 40% similarity (very close, lenient on names)
  - 100-300m: 50% similarity (close, moderate name match needed)
  - 300-800m: 60% similarity (far, good name match needed)
  - 800m+: 75% similarity (very far, strong name match required)
  """
  def should_match?(name1, name2, distance_meters) do
    score = similarity_score(name1, name2)

    required_similarity =
      cond do
        distance_meters < 100 -> 0.40
        distance_meters < 300 -> 0.50
        distance_meters < 800 -> 0.60
        true -> 0.75
      end

    matches = score >= required_similarity

    if matches do
      Logger.info("""
      ✅ Venue name match accepted:
         Name 1: #{name1}
         Name 2: #{name2}
         Distance: #{distance_meters}m
         Similarity: #{Float.round(score * 100, 1)}%
         Required: #{Float.round(required_similarity * 100, 1)}%
      """)
    else
      Logger.debug("""
      ❌ Venue name match rejected:
         Name 1: #{name1}
         Name 2: #{name2}
         Distance: #{distance_meters}m
         Similarity: #{Float.round(score * 100, 1)}%
         Required: #{Float.round(required_similarity * 100, 1)}%
      """)
    end

    matches
  end

  @doc """
  Extract significant tokens from venue name.

  Steps:
  1. Normalize (lowercase, remove punctuation)
  2. Split into tokens
  3. Remove stop words and venue types
  4. Return significant tokens that identify the location
  """
  def extract_significant_tokens(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.normalize(:nfc)
    # Replace hyphens with spaces for better tokenization
    |> String.replace("-", " ")
    # Remove all punctuation except spaces
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
    # Split into tokens
    |> String.split()
    # Remove stop words
    |> Enum.reject(fn token ->
      Enum.member?(@stop_words, token) or Enum.member?(@venue_types, token)
    end)
    # Remove very short tokens (likely not significant)
    |> Enum.reject(fn token -> String.length(token) < 3 end)
  end

  def extract_significant_tokens(_), do: []

  @doc """
  Test the matcher with example venue pairs.
  Useful for validating the algorithm.
  """
  def test_examples do
    examples = [
      # Should MATCH
      {"Cinema City Kazimierz", "Kraków - Galeria Kazimierz", 168},
      {"Cinema City Bonarka", "Kraków - Bonarka", 724},

      # Should NOT MATCH
      {"Cinema City Kazimierz", "Nalej Se", 56},
      {"Goethe-Institut Krakau", "Cinema City Kazimierz", 65},
      {"Regionalne Alkohole", "Cinema City Kazimierz", 593},
      {"Playhaus", "Kraków - Bonarka", 837}
    ]

    IO.puts("\n=== Testing Venue Name Matcher ===\n")

    Enum.each(examples, fn {name1, name2, distance} ->
      score = similarity_score(name1, name2)
      matches = should_match?(name1, name2, distance)

      IO.puts("""
      #{if matches, do: "✅ MATCH", else: "❌ NO MATCH"}
      "#{name1}" vs "#{name2}"
      Distance: #{distance}m | Similarity: #{Float.round(score * 100, 1)}%
      Tokens 1: #{inspect(extract_significant_tokens(name1))}
      Tokens 2: #{inspect(extract_significant_tokens(name2))}
      ---
      """)
    end)
  end
end
