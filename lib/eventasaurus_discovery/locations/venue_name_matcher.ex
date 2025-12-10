defmodule EventasaurusDiscovery.Locations.VenueNameMatcher do
  @moduledoc """
  Sophisticated venue name matching using token-based similarity scoring.

  ## Problem Statement

  Cinema City and Repertuary scrapers were creating duplicate venue records for the same
  physical locations, preventing events from showing as overlapping. This happened because
  different data sources use different naming conventions for the same venues:

  - Cinema City source creates: "Kraków - Bonarka", "Kraków - Galeria Kazimierz"
  - Repertuary source creates: "Cinema City Bonarka", "Cinema City Kazimierz"

  A simple proximity-based match (e.g., "merge all venues within 200m") would create
  false positives in shopping malls where multiple different venues (bars, museums, clubs)
  exist within that radius.

  ## Solution

  Combines distance AND name similarity with adaptive thresholds:
  1. Token extraction (removes stop words like "kraków", "cinema", "galeria")
  2. Jaccard similarity with location bonus for shared significant tokens
  3. Distance-weighted acceptance thresholds (closer = more lenient, farther = stricter)

  ## Baseline Test Cases (Pre-Integration State)

  ### ✅ SHOULD MATCH (Same Physical Location, Different Names)

  These are the same cinemas that should be merged:

  1. **Kazimierz Cinema**
     - Name 1: "Kraków - Galeria Kazimierz" (Cinema City source)
     - Name 2: "Cinema City Kazimierz" (Repertuary source)
     - Distance: 168m
     - Tokens: Both extract "kazimierz" as significant token
     - Status: ❌ Currently SEPARATE venues (IDs: 154, 311)
     - Impact: 2 Bugonia events split across venues

  2. **Bonarka Cinema**
     - Name 1: "Kraków - Bonarka" (Cinema City source)
     - Name 2: "Cinema City Bonarka" (Repertuary source)
     - Distance: 724m
     - Tokens: Both extract "bonarka" as significant token
     - Status: ❌ Currently SEPARATE venues (IDs: 161, 289)
     - Impact: 2 Bugonia events split across venues

  3. **Zakopianka Cinema**
     - Name 1: "Kraków - Zakopianka" (Cinema City source)
     - Name 2: "Cinema City Zakopianka" (Repertuary source)
     - Distance: 173m
     - Tokens: Both extract "zakopianka" as significant token
     - Status: ❌ Currently SEPARATE venues (IDs: 157, 397)

  ### ❌ SHOULD NOT MATCH (Different Venues, False Positives)

  These are different venues that should remain separate even though they're close:

  1. "Kraków - Galeria Kazimierz" vs "Nalej Se" (bar) - 56m
     - Tokens: ["kazimierz"] vs ["nalej"] = 0% match
     - Verdict: ✅ Correctly rejected (no shared tokens)

  2. "Goethe-Institut Krakau" vs "Cinema City Kazimierz" (cultural institute) - 65m
     - Tokens: ["goethe", "institut", "krakau"] vs ["kazimierz"] = 0% match
     - Verdict: ✅ Correctly rejected

  3. "Regionalne Alkohole" vs "Cinema City Kazimierz" (alcohol store) - 593m
     - Tokens: ["regionalne", "alkohole"] vs ["kazimierz"] = 0% match
     - Verdict: ✅ Correctly rejected

  4. "Playhaus" vs "Kraków - Bonarka" (different venue) - 837m
     - Tokens: ["playhaus"] vs ["bonarka"] = 0% match
     - Verdict: ✅ Correctly rejected

  5. "Muzeum Banksy" vs "Cinema City Kazimierz" (museum) - 668m
  6. "Sekta Selekta" vs "Cinema City Kazimierz" (club) - 714m
  7. "Cricoteka" vs "Cinema City Kazimierz" (museum) - 740m
  8. "Hala Lipowa" vs "Kraków - Galeria Kazimierz" (venue) - 646m
  9. "Krakowski Teatr Variété" vs "Kraków - Galeria Kazimierz" (theater) - 679m
  10. "Oliwa Pub" vs "Cinema City Kazimierz" (pub) - 778m
  11. "Teatr Współczesny" vs "Cinema City Kazimierz" (theater) - 836m
  12. "SLAY SPACE" vs "Cinema City Kazimierz" (venue) - 840m
  13. "Piękny Pies" vs "Cinema City Kazimierz" (venue) - 846m
  14. "La Forchetta na nowo" vs "Cinema City Zakopianka" (restaurant) - 860m
  15. "Lokator" vs "Cinema City Kazimierz" (venue) - 876m
  16. "Pałac Nieśmiertelności" vs "Cinema City Kazimierz" (venue) - 918m
  17. "Centrum Sztuki Współczesnej Solvay" vs "Cinema City Zakopianka" (art center) - 303m

  ## Expected Post-Integration State

  After deleting duplicate venues and re-running scrapers with this matcher:

  1. ✅ Cinema City Kazimierz & Cinema City Kazimierz → MERGED (1 venue)
  2. ✅ Cinema City Bonarka & Cinema City Bonarka → MERGED (1 venue)
  3. ✅ Cinema City Zakopianka & Cinema City Zakopianka → MERGED (1 venue)
  4. ✅ All bars, museums, clubs remain SEPARATE
  5. ✅ Bugonia events from both sources appear together on the same venue page

  ## Algorithm Details

  Distance-weighted similarity thresholds:
  - 0-100m: 40% similarity required (very close, lenient on names)
  - 100-300m: 50% similarity (close, moderate name match needed)
  - 300-800m: 60% similarity (far, good name match needed)
  - 800m+: 75% similarity (very far, strong name match required)

  Token extraction removes:
  - Stop words: krakow, kraków, krakau, cinema, city, galeria, gallery, the, at, in
  - Venue types: arena, stadium, club, hall, theater, centre, bar, lounge, pub, house, etc.
  - Tokens shorter than 3 characters

  Jaccard similarity with location bonus:
  - Base: |A ∩ B| / |A ∪ B| (overlap / total unique tokens)
  - Bonus: +20% if any shared significant token exists
  - Capped at 100%
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
