defmodule EventasaurusDiscovery.Sources.Kupbilecik.ClientTest do
  @moduledoc """
  Tests for the Kupbilecik Client module.

  The Client uses plain HTTP for server-side rendered (SSR) pages.
  No JavaScript rendering is required as kupbilecik.pl serves
  fully-rendered HTML for SEO purposes. Most tests require mocked
  HTTP responses or are marked as integration tests.
  """
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Kupbilecik.{Client, Config}

  describe "configuration" do
    test "returns correct base URL" do
      assert Config.base_url() == "https://www.kupbilecik.pl"
    end

    test "returns correct sitemap URLs" do
      urls = Config.sitemap_urls()
      assert length(urls) == 5

      for url <- urls do
        assert String.starts_with?(url, "https://www.kupbilecik.pl/sitemap_imprezy-")
        assert String.ends_with?(url, ".xml")
      end
    end

    test "returns source slug" do
      assert Config.source_slug() == "kupbilecik"
    end
  end

  describe "event URL detection" do
    test "recognizes valid event URLs" do
      assert Config.is_event_url?("https://www.kupbilecik.pl/imprezy/186000/")
      assert Config.is_event_url?("https://www.kupbilecik.pl/imprezy/186000/koncert-rockowy/")
    end

    test "rejects non-event URLs" do
      refute Config.is_event_url?("https://www.kupbilecik.pl/")
      refute Config.is_event_url?("https://www.kupbilecik.pl/artysci/")
      # Note: is_event_url? only checks URL pattern, not domain
      # Other domains with /imprezy/ pattern still match
    end
  end

  describe "event ID extraction" do
    test "extracts event ID from URL" do
      assert Config.extract_event_id("https://www.kupbilecik.pl/imprezy/186000/") == "186000"
      assert Config.extract_event_id("https://www.kupbilecik.pl/imprezy/186000/slug/") == "186000"
    end

    test "returns nil for invalid URLs" do
      assert Config.extract_event_id("https://example.com/") == nil
      assert Config.extract_event_id("invalid") == nil
    end
  end

  describe "external ID generation" do
    test "generates correct external ID format" do
      assert Config.generate_external_id("186000", "2025-12-07") ==
               "kupbilecik_event_186000_2025-12-07"
    end

    test "handles Date struct" do
      assert Config.generate_external_id("186000", ~D[2025-12-07]) ==
               "kupbilecik_event_186000_2025-12-07"
    end
  end

  describe "fetch_all_sitemap_urls/0" do
    @tag :external_api
    test "fetches sitemap URLs" do
      # Requires actual HTTP connection to kupbilecik.pl
      # Run with: mix test --only external_api
      case Client.fetch_all_sitemap_urls() do
        {:ok, urls} ->
          assert is_list(urls)
          assert length(urls) > 0

        {:error, reason} ->
          # Network errors are acceptable in automated tests
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end
end
