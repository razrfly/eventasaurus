defmodule EventasaurusWeb.Plugs.ConditionalSessionPlugTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EventasaurusWeb.Plugs.ConditionalSessionPlug

  describe "cacheable routes without auth cookie" do
    test "marks /activities/:slug as cacheable" do
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:skip_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "marks /activities/:slug/:date_slug as cacheable" do
      conn =
        :get
        |> conn("/activities/summer-festival/2025-01-15")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:skip_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "handles slug with special characters" do
      conn =
        :get
        |> conn("/activities/my-awesome-event-123")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:skip_session] == true
      assert conn.assigns[:cacheable_request] == true
    end
  end

  describe "non-cacheable routes without auth cookie" do
    test "does not mark /activities index as cacheable" do
      conn =
        :get
        |> conn("/activities")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:skip_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark / as cacheable" do
      conn =
        :get
        |> conn("/")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:skip_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark /venues/:slug as cacheable (Phase 2)" do
      conn =
        :get
        |> conn("/venues/some-venue")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:skip_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark nested paths beyond two segments as cacheable" do
      conn =
        :get
        |> conn("/activities/slug/date/extra")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:skip_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "authenticated users (has __session cookie)" do
    test "does not mark cacheable route as cacheable when authenticated" do
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:skip_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark date-based route as cacheable when authenticated" do
      conn =
        :get
        |> conn("/activities/summer-festival/2025-01-15")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:skip_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "edge cases" do
    test "empty __session cookie is treated as anonymous" do
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("__session", "")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:skip_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "other cookies without __session are treated as anonymous" do
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("other_cookie", "some-value")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:skip_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "whitespace-only __session cookie in test is normalized to empty" do
      # Note: Plug.Test normalizes whitespace-only cookies to empty strings
      # In production, whitespace would be preserved and treated as authenticated
      # This test documents the test infrastructure behavior
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("__session", "   ")
        |> ConditionalSessionPlug.call([])

      # Test infrastructure normalizes "   " to "", so treated as anonymous
      assert conn.assigns[:skip_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "real token is treated as authenticated" do
      # Any real token value prevents caching
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("__session", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:skip_session]
      refute conn.assigns[:cacheable_request]
    end
  end
end
