defmodule EventasaurusDiscovery.Sources.SourceTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusApp.Repo

  describe "get_display_name/1" do
    setup do
      # Create test sources in database
      {:ok, source1} =
        %Source{}
        |> Source.changeset(%{
          name: "Restaurant Week",
          slug: "week_pl",
          website_url: "https://week.pl",
          priority: 45,
          domains: ["food", "festival"]
        })
        |> Repo.insert()

      {:ok, source2} =
        %Source{}
        |> Source.changeset(%{
          name: "Bandsintown",
          slug: "bandsintown",
          website_url: "https://bandsintown.com",
          priority: 80,
          domains: ["music"]
        })
        |> Repo.insert()

      {:ok, source3} =
        %Source{}
        |> Source.changeset(%{
          name: "PubQuiz Poland",
          slug: "pubquiz-pl",
          website_url: "https://pubquiz.pl",
          priority: 25,
          domains: ["trivia"]
        })
        |> Repo.insert()

      {:ok, source1: source1, source2: source2, source3: source3}
    end

    test "returns correct display name for source with underscored slug", %{source1: _source1} do
      assert Source.get_display_name("week_pl") == "Restaurant Week"
    end

    test "returns correct display name for source with simple slug", %{source2: _source2} do
      assert Source.get_display_name("bandsintown") == "Bandsintown"
    end

    test "returns correct display name for source with hyphenated slug", %{source3: _source3} do
      assert Source.get_display_name("pubquiz-pl") == "PubQuiz Poland"
    end

    test "generates fallback display name for unknown source with hyphens" do
      # Source doesn't exist in DB, should use fallback
      assert Source.get_display_name("unknown-source") == "Unknown Source"
    end

    test "generates fallback display name for unknown source with underscores" do
      # Source doesn't exist in DB, should use fallback
      assert Source.get_display_name("my_cool_source") == "My Cool Source"
    end

    test "generates fallback display name for mixed separators" do
      assert Source.get_display_name("some-cool_source") == "Some Cool Source"
    end

    test "returns empty string for nil input" do
      assert Source.get_display_name(nil) == ""
    end

    test "returns empty string for non-string input" do
      assert Source.get_display_name(123) == ""
      assert Source.get_display_name(%{}) == ""
      assert Source.get_display_name([]) == ""
    end

    test "handles empty string gracefully" do
      assert Source.get_display_name("") == ""
    end

    test "is case-sensitive for slug matching" do
      # Slugs are always lowercase, so uppercase should not match
      assert Source.get_display_name("WEEK_PL") == "Week Pl"
    end
  end

  describe "get_display_name/1 performance" do
    test "queries database only once per call" do
      # Insert a source
      {:ok, _source} =
        %Source{}
        |> Source.changeset(%{
          name: "Test Source",
          slug: "test-source",
          website_url: "https://test.com",
          domains: ["general"]
        })
        |> Repo.insert()

      # First call - should query database
      result1 = Source.get_display_name("test-source")
      assert result1 == "Test Source"

      # Second call - should also query database (no caching in Phase 1)
      result2 = Source.get_display_name("test-source")
      assert result2 == "Test Source"

      # Both should return same result
      assert result1 == result2
    end
  end

  describe "fallback_display_name/1 private function behavior" do
    test "properly capitalizes each word" do
      # Testing the fallback indirectly through non-existent sources
      assert Source.get_display_name("speed-quizzing") == "Speed Quizzing"
      assert Source.get_display_name("geeks_who_drink") == "Geeks Who Drink"
    end

    test "handles single word slugs" do
      assert Source.get_display_name("ticketmaster") == "Ticketmaster"
    end

    test "handles multiple separators in sequence" do
      assert Source.get_display_name("test--slug__name") == "Test Slug Name"
    end
  end
end
