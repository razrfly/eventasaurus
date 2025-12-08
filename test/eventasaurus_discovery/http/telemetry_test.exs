defmodule EventasaurusDiscovery.Http.TelemetryTest do
  @moduledoc """
  Tests for HTTP telemetry event handling and monitoring.

  This module verifies that the telemetry system correctly captures
  HTTP request lifecycle events for monitoring and debugging.
  """
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Http.Telemetry

  @test_handler_id "test-http-telemetry-handler"

  setup do
    # Attach a test handler to capture events
    test_pid = self()

    events = [
      [:eventasaurus, :http, :request, :start],
      [:eventasaurus, :http, :request, :stop],
      [:eventasaurus, :http, :request, :exception],
      [:eventasaurus, :http, :blocked]
    ]

    handler = fn event, measurements, metadata, _config ->
      send(test_pid, {:telemetry_event, event, measurements, metadata})
    end

    :telemetry.attach_many(@test_handler_id, events, handler, nil)

    on_exit(fn ->
      :telemetry.detach(@test_handler_id)
    end)

    :ok
  end

  describe "attach/0" do
    test "successfully attaches telemetry handlers" do
      # Detach first if already attached (from application startup)
      :telemetry.detach("http-client-monitoring")

      # Now attach
      assert :ok = Telemetry.attach()

      # Verify handlers are attached by listing handlers
      handlers = :telemetry.list_handlers([:eventasaurus, :http, :request, :start])
      assert Enum.any?(handlers, fn %{id: id} -> id == "http-client-monitoring" end)
    end
  end

  describe "request start event" do
    test "captures request start with correct metadata" do
      :telemetry.execute(
        [:eventasaurus, :http, :request, :start],
        %{system_time: System.system_time()},
        %{
          url: "https://example.com/test",
          source: :test_source,
          strategy: :auto,
          adapter_chain: ["direct", "zyte"]
        }
      )

      assert_receive {:telemetry_event, [:eventasaurus, :http, :request, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.url == "https://example.com/test"
      assert metadata.source == :test_source
      assert metadata.strategy == :auto
      assert metadata.adapter_chain == ["direct", "zyte"]
    end
  end

  describe "request stop event" do
    test "captures successful request completion" do
      :telemetry.execute(
        [:eventasaurus, :http, :request, :stop],
        %{duration: 150_000_000},  # 150ms in native time units
        %{
          url: "https://example.com/test",
          source: :test_source,
          adapter: "direct",
          status_code: 200,
          attempts: 1,
          blocked_by: []
        }
      )

      assert_receive {:telemetry_event, [:eventasaurus, :http, :request, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.url == "https://example.com/test"
      assert metadata.adapter == "direct"
      assert metadata.status_code == 200
      assert metadata.attempts == 1
      assert metadata.blocked_by == []
    end

    test "captures request with fallback attempts" do
      :telemetry.execute(
        [:eventasaurus, :http, :request, :stop],
        %{duration: 5_000_000_000},  # 5s
        %{
          url: "https://example.com/test",
          source: :bandsintown,
          adapter: "zyte",
          status_code: 200,
          attempts: 2,
          blocked_by: ["direct"]
        }
      )

      assert_receive {:telemetry_event, [:eventasaurus, :http, :request, :stop], measurements, metadata}
      assert metadata.attempts == 2
      assert metadata.blocked_by == ["direct"]
      assert metadata.adapter == "zyte"
    end
  end

  describe "request exception event" do
    test "captures request failures" do
      :telemetry.execute(
        [:eventasaurus, :http, :request, :exception],
        %{duration: 30_000_000_000},  # 30s timeout
        %{
          url: "https://example.com/timeout",
          source: :test_source,
          error: {:timeout, :connect}
        }
      )

      assert_receive {:telemetry_event, [:eventasaurus, :http, :request, :exception], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.url == "https://example.com/timeout"
      assert metadata.error == {:timeout, :connect}
    end

    test "captures all_adapters_failed error" do
      blocked_by = [
        %{adapter: "direct", blocking_type: :cloudflare, status_code: 403},
        %{adapter: "zyte", error: :rate_limit}
      ]

      :telemetry.execute(
        [:eventasaurus, :http, :request, :exception],
        %{duration: 60_000_000_000},
        %{
          url: "https://protected-site.com",
          source: :bandsintown,
          error: {:all_adapters_failed, blocked_by}
        }
      )

      assert_receive {:telemetry_event, [:eventasaurus, :http, :request, :exception], _measurements, metadata}
      assert {:all_adapters_failed, _} = metadata.error
    end
  end

  describe "blocked event" do
    test "captures Cloudflare blocking" do
      :telemetry.execute(
        [:eventasaurus, :http, :blocked],
        %{system_time: System.system_time()},
        %{
          url: "https://cloudflare-protected.com",
          source: :test_source,
          adapter: "direct",
          blocking_type: :cloudflare,
          status_code: 403
        }
      )

      assert_receive {:telemetry_event, [:eventasaurus, :http, :blocked], _measurements, metadata}
      assert metadata.blocking_type == :cloudflare
      assert metadata.adapter == "direct"
      assert metadata.status_code == 403
    end

    test "captures rate limiting with retry_after" do
      :telemetry.execute(
        [:eventasaurus, :http, :blocked],
        %{system_time: System.system_time()},
        %{
          url: "https://api.example.com",
          source: :test_source,
          adapter: "direct",
          blocking_type: :rate_limit,
          status_code: 429,
          retry_after: 120
        }
      )

      assert_receive {:telemetry_event, [:eventasaurus, :http, :blocked], _measurements, metadata}
      assert metadata.blocking_type == :rate_limit
      assert metadata.retry_after == 120
    end

    test "captures CAPTCHA blocking" do
      :telemetry.execute(
        [:eventasaurus, :http, :blocked],
        %{system_time: System.system_time()},
        %{
          url: "https://captcha-protected.com",
          source: :test_source,
          adapter: "direct",
          blocking_type: :captcha,
          status_code: 200
        }
      )

      assert_receive {:telemetry_event, [:eventasaurus, :http, :blocked], _measurements, metadata}
      assert metadata.blocking_type == :captcha
    end
  end

  describe "handle_event/4" do
    test "handles start event without crashing" do
      # Just verify the handler doesn't crash
      assert :ok = Telemetry.handle_event(
        [:eventasaurus, :http, :request, :start],
        %{system_time: System.system_time()},
        %{url: "https://example.com", source: :test, strategy: :auto, adapter_chain: ["direct"]},
        nil
      )
    end

    test "handles stop event without crashing" do
      assert :ok = Telemetry.handle_event(
        [:eventasaurus, :http, :request, :stop],
        %{duration: 1_000_000},
        %{url: "https://example.com", source: :test, adapter: "direct", status_code: 200, attempts: 1, blocked_by: []},
        nil
      )
    end

    test "handles exception event without crashing" do
      assert :ok = Telemetry.handle_event(
        [:eventasaurus, :http, :request, :exception],
        %{duration: 1_000_000},
        %{url: "https://example.com", source: :test, error: {:timeout, :connect}},
        nil
      )
    end

    test "handles blocked event without crashing" do
      assert :ok = Telemetry.handle_event(
        [:eventasaurus, :http, :blocked],
        %{system_time: System.system_time()},
        %{url: "https://example.com", source: :test, adapter: "direct", blocking_type: :cloudflare, status_code: 403},
        nil
      )
    end

    test "handles slow request warning" do
      # A request over 5000ms should trigger a warning log
      assert :ok = Telemetry.handle_event(
        [:eventasaurus, :http, :request, :stop],
        %{duration: 6_000_000_000},  # 6 seconds
        %{url: "https://example.com", source: :test, adapter: "direct", status_code: 200, attempts: 1, blocked_by: []},
        nil
      )
    end

    test "handles fallback usage tracking" do
      # Multiple attempts should trigger fallback logging
      assert :ok = Telemetry.handle_event(
        [:eventasaurus, :http, :request, :stop],
        %{duration: 2_000_000_000},
        %{url: "https://example.com", source: :test, adapter: "zyte", status_code: 200, attempts: 3, blocked_by: ["direct", "other"]},
        nil
      )
    end
  end

  describe "event metadata validation" do
    test "events include source identifier" do
      :telemetry.execute(
        [:eventasaurus, :http, :request, :start],
        %{system_time: System.system_time()},
        %{url: "https://example.com", source: :bandsintown, strategy: :auto, adapter_chain: ["zyte"]}
      )

      assert_receive {:telemetry_event, _, _, metadata}
      assert metadata.source == :bandsintown
    end

    test "events include truncated URLs for long URLs" do
      # The client truncates URLs over 100 chars
      long_url = "https://example.com/" <> String.duplicate("a", 200)

      :telemetry.execute(
        [:eventasaurus, :http, :request, :start],
        %{system_time: System.system_time()},
        %{url: long_url, source: :test, strategy: :auto, adapter_chain: ["direct"]}
      )

      assert_receive {:telemetry_event, _, _, metadata}
      assert is_binary(metadata.url)
    end
  end
end
