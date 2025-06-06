defmodule EventasaurusWeb.HealthControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns overall system health status", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert %{
        "status" => "healthy",
        "timestamp" => _timestamp,
        "checks" => checks
      } = response

      assert %{
        "database" => %{"status" => "healthy"},
        "supabase" => %{"status" => _supabase_status},
        "application" => %{"status" => "healthy"}
      } = checks
    end

    test "includes application metrics in response", %{conn: conn} do
      conn = get(conn, ~p"/health")
      response = json_response(conn, 200)

      application_check = response["checks"]["application"]

      assert application_check["uptime"]
      assert application_check["memory_usage"]
      assert application_check["message"] == "Application running normally"
    end
  end

  describe "GET /health/auth" do
    test "returns authentication system health status", %{conn: conn} do
      conn = get(conn, ~p"/health/auth")

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert %{
        "status" => "healthy",
        "timestamp" => _timestamp,
        "checks" => checks
      } = response

      assert %{
        "auth_endpoints" => %{"status" => "healthy"},
        "email_service" => %{"status" => _email_status},
        "session_storage" => %{"status" => "healthy"},
        "supabase_auth" => %{"status" => _supabase_auth_status}
      } = checks
    end

    test "includes authentication endpoint information", %{conn: conn} do
      conn = get(conn, ~p"/health/auth")
      response = json_response(conn, 200)

      auth_endpoints_check = response["checks"]["auth_endpoints"]

      assert auth_endpoints_check["endpoints"] == [
        "POST /auth/register",
        "POST /auth/login",
        "GET /auth/callback"
      ]
    end

    test "includes session storage information", %{conn: conn} do
      conn = get(conn, ~p"/health/auth")
      response = json_response(conn, 200)

      session_check = response["checks"]["session_storage"]

      assert session_check["storage_type"] == "LiveView sessions"
      assert session_check["message"] == "Session storage operational"
    end
  end

  describe "health check status codes" do
    test "returns 200 when all systems healthy", %{conn: conn} do
      conn = get(conn, ~p"/health")
      assert conn.status == 200
    end

    test "auth health returns 200 when auth systems healthy", %{conn: conn} do
      conn = get(conn, ~p"/health/auth")
      assert conn.status == 200
    end
  end

    describe "timestamp format" do
    test "returns valid ISO8601 timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health")
      response = json_response(conn, 200)

      timestamp = response["timestamp"]

      # Should be able to parse as DateTime
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(timestamp)
    end
  end
end
