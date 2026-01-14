defmodule EventasaurusDiscovery.Movies.ImdbServiceTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Movies.ImdbService

  describe "parse_search_results/1" do
    test "extracts movie from modern IMDB layout with year" do
      html = """
      <ul>
        <li>
          <a href="/title/tt0047478/" class="result-link">Seven Samurai</a> (1954)
        </li>
      </ul>
      """

      results = ImdbService.parse_search_results(html)

      assert length(results) == 1
      [result] = results
      assert result.imdb_id == "tt0047478"
      assert result.title == "Seven Samurai"
      assert result.year == 1954
    end

    test "extracts multiple movies" do
      html = """
      <div>
        <a href="/title/tt0047478/">Seven Samurai</a> (1954)
        <a href="/title/tt0038650/">It's a Wonderful Life</a> (1946)
      </div>
      """

      results = ImdbService.parse_search_results(html)

      assert length(results) == 2
      assert Enum.any?(results, &(&1.imdb_id == "tt0047478"))
      assert Enum.any?(results, &(&1.imdb_id == "tt0038650"))
    end

    test "deduplicates results by IMDB ID" do
      html = """
      <div>
        <a href="/title/tt0047478/">Seven Samurai</a> (1954)
        <a href="/title/tt0047478/">Shichinin no samurai</a> (1954)
      </div>
      """

      results = ImdbService.parse_search_results(html)

      # Should only have one result despite two links to same movie
      assert length(results) == 1
      assert hd(results).imdb_id == "tt0047478"
    end

    test "handles missing year gracefully" do
      html = """
      <div>
        <a href="/title/tt0047478/">Seven Samurai</a>
      </div>
      """

      results = ImdbService.parse_search_results(html)

      assert length(results) == 1
      [result] = results
      assert result.imdb_id == "tt0047478"
      assert result.title == "Seven Samurai"
      # Year may be nil if not found near the title
      assert is_nil(result.year) or is_integer(result.year)
    end

    test "returns empty list for HTML without movie results" do
      html = """
      <html>
        <body>
          <p>No results found</p>
        </body>
      </html>
      """

      results = ImdbService.parse_search_results(html)
      assert results == []
    end

    test "handles legacy IMDB layout" do
      html = """
      <td class="result_text">
        <a href="/title/tt0047478/">Seven Samurai</a> (1954)
      </td>
      """

      results = ImdbService.parse_search_results(html)

      assert length(results) == 1
      [result] = results
      assert result.imdb_id == "tt0047478"
      assert result.year == 1954
    end

    test "extracts IMDB ID from various URL formats" do
      html = """
      <a href="/title/tt0047478/?ref_=fn_al_tt_1">Seven Samurai</a> (1954)
      <a href="/title/tt0038650/reference">It's a Wonderful Life</a> (1946)
      """

      results = ImdbService.parse_search_results(html)

      imdb_ids = Enum.map(results, & &1.imdb_id)
      assert "tt0047478" in imdb_ids
      assert "tt0038650" in imdb_ids
    end
  end

  describe "search/2" do
    @tag :integration
    @tag :external
    test "returns error when Crawlbase is not configured" do
      # This test will pass if CRAWLBASE_JS_API_KEY is not set
      unless EventasaurusDiscovery.Http.Adapters.Crawlbase.available_for_mode?(:javascript) do
        result = ImdbService.search("Seven Samurai")
        assert {:error, :crawlbase_not_configured} = result
      end
    end
  end

  describe "available?/0" do
    test "returns boolean indicating Crawlbase availability" do
      result = ImdbService.available?()
      assert is_boolean(result)
    end
  end
end
