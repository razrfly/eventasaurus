defmodule EventasaurusWeb.WebhookSmokeTest do
  @moduledoc """
  Basic smoke tests for webhook functionality.
  Very simple tests to ensure webhook endpoints work without complex Stripe mocking.
  """

  use EventasaurusWeb.ConnCase

  describe "stripe webhook smoke tests" do
    test "webhook endpoint exists and responds", %{conn: conn} do
      # Just verify the endpoint exists and returns proper error for invalid requests
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/webhooks/stripe/", "{\"invalid\": \"json\"}")

      # Should respond with some error (not 404), proving endpoint exists
      assert conn.status != 404
      # Should be some form of client error or server handling
      assert conn.status >= 400
    end
  end
end
