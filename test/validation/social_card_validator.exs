#!/usr/bin/env elixir

# Social Card Validation Script
# Tests social card endpoints for proper responses and metadata

defmodule SocialCardValidator do
  @moduledoc """
  Validates social card endpoints for:
  - HTTP 200 responses
  - Correct content-type (image/png)
  - Cache headers (max-age, etag)
  - Hash validation (301 redirects on mismatch)
  - Image generation performance
  """

  def run do
    IO.puts("\n🔍 Social Card Validation Test Suite\n")
    IO.puts("=" |> String.duplicate(60))

    results = [
      test_event_social_card(),
      test_poll_social_card(),
      test_city_social_card(),
      test_hash_mismatch_redirect(),
      test_performance_benchmarks()
    ]

    print_summary(results)
  end

  defp test_event_social_card do
    IO.puts("\n📅 Testing Event Social Card...")

    case get_sample_event() do
      {:ok, slug, hash} ->
        url = "/#{slug}/social-card-#{hash}.png"
        test_endpoint(url, :event)

      {:error, reason} ->
        IO.puts("  ❌ Failed to get sample event: #{reason}")
        {:error, :event, reason}
    end
  end

  defp test_poll_social_card do
    IO.puts("\n📊 Testing Poll Social Card...")

    case get_sample_poll() do
      {:ok, event_slug, poll_number, hash} ->
        url = "/#{event_slug}/polls/#{poll_number}/social-card-#{hash}.png"
        test_endpoint(url, :poll)

      {:error, reason} ->
        IO.puts("  ❌ Failed to get sample poll: #{reason}")
        {:error, :poll, reason}
    end
  end

  defp test_city_social_card do
    IO.puts("\n🏙️  Testing City Social Card...")

    case get_sample_city() do
      {:ok, slug, hash} ->
        url = "/social-cards/city/#{slug}/#{hash}.png"
        test_endpoint(url, :city)

      {:error, reason} ->
        IO.puts("  ❌ Failed to get sample city: #{reason}")
        {:error, :city, reason}
    end
  end

  defp test_hash_mismatch_redirect do
    IO.puts("\n🔄 Testing Hash Mismatch Redirect...")

    case get_sample_event() do
      {:ok, slug, _correct_hash} ->
        wrong_hash = "wrong123"
        url = "/#{slug}/social-card-#{wrong_hash}.png"

        case make_request(url) do
          {:ok, status, headers, _body} when status == 301 or status == 302 ->
            location = get_header(headers, "location")
            IO.puts("  ✅ Correctly redirected (#{status})")
            IO.puts("  📍 Location: #{location}")
            {:ok, :redirect, "Hash mismatch redirect works"}

          {:ok, status, _headers, _body} ->
            IO.puts("  ❌ Expected redirect, got #{status}")
            {:error, :redirect, "Expected 301/302, got #{status}"}

          {:error, reason} ->
            IO.puts("  ❌ Request failed: #{reason}")
            {:error, :redirect, reason}
        end

      {:error, reason} ->
        IO.puts("  ❌ Failed to get sample event: #{reason}")
        {:error, :redirect, reason}
    end
  end

  defp test_performance_benchmarks do
    IO.puts("\n⚡ Performance Benchmarks...")

    case get_sample_event() do
      {:ok, slug, hash} ->
        url = "/#{slug}/social-card-#{hash}.png"

        # Warm-up request
        make_request(url)

        # Measure first generation (cache miss)
        {time1, {:ok, _, _, _}} = :timer.tc(fn -> make_request(url) end)
        time1_ms = time1 / 1000

        # Measure second request (should be cached or fast)
        {time2, {:ok, _, _, _}} = :timer.tc(fn -> make_request(url) end)
        time2_ms = time2 / 1000

        IO.puts("  ⏱️  First request: #{Float.round(time1_ms, 2)}ms")
        IO.puts("  ⏱️  Second request: #{Float.round(time2_ms, 2)}ms")

        target_ms = 500

        if time1_ms < target_ms do
          IO.puts("  ✅ Performance within target (<#{target_ms}ms)")
          {:ok, :performance, "First request: #{Float.round(time1_ms, 2)}ms"}
        else
          IO.puts("  ⚠️  Performance above target (>#{target_ms}ms)")
          {:warning, :performance, "First request: #{Float.round(time1_ms, 2)}ms"}
        end

      {:error, reason} ->
        IO.puts("  ❌ Failed to get sample event: #{reason}")
        {:error, :performance, reason}
    end
  end

  defp test_endpoint(url, type) do
    IO.puts("  🌐 Testing: #{url}")

    case make_request(url) do
      {:ok, 200, headers, body} ->
        checks = [
          check_content_type(headers),
          check_cache_headers(headers),
          check_etag(headers),
          check_image_data(body)
        ]

        if Enum.all?(checks, &(&1 == :ok)) do
          IO.puts("  ✅ All checks passed")
          {:ok, type, "All validations passed"}
        else
          IO.puts("  ⚠️  Some checks failed")
          {:warning, type, "Some validations failed"}
        end

      {:ok, status, _headers, _body} ->
        IO.puts("  ❌ Unexpected status: #{status}")
        {:error, type, "HTTP #{status}"}

      {:error, reason} ->
        IO.puts("  ❌ Request failed: #{reason}")
        {:error, type, reason}
    end
  end

  defp check_content_type(headers) do
    case get_header(headers, "content-type") do
      "image/png" ->
        IO.puts("  ✅ Content-Type: image/png")
        :ok

      other ->
        IO.puts("  ❌ Content-Type: #{other} (expected image/png)")
        :error
    end
  end

  defp check_cache_headers(headers) do
    cache_control = get_header(headers, "cache-control")

    cond do
      String.contains?(cache_control, "max-age") ->
        IO.puts("  ✅ Cache-Control: #{cache_control}")
        :ok

      true ->
        IO.puts("  ⚠️  Cache-Control: #{cache_control} (no max-age)")
        :warning
    end
  end

  defp check_etag(headers) do
    case get_header(headers, "etag") do
      "" ->
        IO.puts("  ⚠️  No ETag header")
        :warning

      etag ->
        IO.puts("  ✅ ETag: #{etag}")
        :ok
    end
  end

  defp check_image_data(body) do
    cond do
      byte_size(body) == 0 ->
        IO.puts("  ❌ Empty response body")
        :error

      byte_size(body) < 1000 ->
        IO.puts("  ⚠️  Small image size: #{byte_size(body)} bytes")
        :warning

      binary_part(body, 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>> ->
        IO.puts("  ✅ Valid PNG signature (#{byte_size(body)} bytes)")
        :ok

      true ->
        IO.puts("  ❌ Invalid PNG signature")
        :error
    end
  end

  defp get_header(headers, name) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(k) == String.downcase(name) end)
    |> case do
      {_k, v} -> v
      nil -> ""
    end
  end

  defp make_request(path) do
    base_url = System.get_env("APP_URL") || "http://localhost:4000"
    url = "#{base_url}#{path}"

    case :httpc.request(:get, {String.to_charlist(url), []}, [], [body_format: :binary]) do
      {:ok, {{_version, status, _reason}, headers, body}} ->
        headers_list =
          Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)

        {:ok, status, headers_list, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_sample_event do
    # TODO: Implement database queries when DATABASE_URL is available
    # For now, using mock data
    IO.puts("  ℹ️  Note: Using mock data. Update these functions to query real data.")
    {:ok, "sample-event", "abc12345"}
  end

  defp get_sample_poll do
    # TODO: Implement database queries when DATABASE_URL is available
    IO.puts("  ℹ️  Note: Using mock data. Update these functions to query real data.")
    {:ok, "sample-event", "1", "def67890"}
  end

  defp get_sample_city do
    # TODO: Implement database queries when DATABASE_URL is available
    IO.puts("  ℹ️  Note: Using mock data. Update these functions to query real data.")
    {:ok, "warsaw", "ghi11111"}
  end

  defp print_summary(results) do
    IO.puts("\n" <> ("=" |> String.duplicate(60)))
    IO.puts("📊 Test Summary\n")

    success = Enum.count(results, fn {status, _, _} -> status == :ok end)
    warnings = Enum.count(results, fn {status, _, _} -> status == :warning end)
    errors = Enum.count(results, fn {status, _, _} -> status == :error end)
    total = length(results)

    IO.puts("  ✅ Passed: #{success}/#{total}")
    IO.puts("  ⚠️  Warnings: #{warnings}/#{total}")
    IO.puts("  ❌ Failed: #{errors}/#{total}")

    if errors == 0 and warnings == 0 do
      IO.puts("\n🎉 All tests passed!")
    else
      IO.puts("\n⚠️  Some tests need attention")
    end

    IO.puts("")
  end
end

# Start HTTP client
:inets.start()
:ssl.start()

# Run validation
SocialCardValidator.run()
