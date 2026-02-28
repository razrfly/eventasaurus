defmodule CinegraphTestPlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    {status, body} = Agent.get(:cinegraph_test_response, & &1)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end
end

defmodule EventasaurusWeb.Services.CinegraphClientTest do
  # async: false because tests mutate global state via Application.put_env
  use ExUnit.Case, async: false

  alias EventasaurusWeb.Services.CinegraphClient

  @port 18_234

  setup_all do
    {:ok, _} = Agent.start_link(fn -> {200, ""} end, name: :cinegraph_test_response)
    {:ok, _} = Plug.Cowboy.http(CinegraphTestPlug, [], port: @port)

    on_exit(fn ->
      Plug.Cowboy.shutdown(CinegraphTestPlug.HTTP)
      Agent.stop(:cinegraph_test_response)
    end)

    :ok
  end

  setup do
    original = Application.get_env(:eventasaurus, :cinegraph, [])
    on_exit(fn -> Application.put_env(:eventasaurus, :cinegraph, original) end)
    :ok
  end

  defp set_response(status, body),
    do: Agent.update(:cinegraph_test_response, fn _ -> {status, body} end)

  # MARK: - API Key Validation

  describe "get_movie/1 — API key validation" do
    test "returns :missing_api_key when api_key is nil" do
      Application.put_env(:eventasaurus, :cinegraph, api_key: nil)
      assert {:error, :missing_api_key} = CinegraphClient.get_movie(12345)
    end

    test "returns :missing_api_key when api_key is empty string" do
      Application.put_env(:eventasaurus, :cinegraph, api_key: "")
      assert {:error, :missing_api_key} = CinegraphClient.get_movie(12345)
    end
  end

  # MARK: - Successful 200 Responses

  describe "get_movie/1 — successful response" do
    setup do
      Application.put_env(:eventasaurus, :cinegraph,
        api_key: "test-key",
        base_url: "http://localhost:#{@port}"
      )

      :ok
    end

    test "returns {:ok, data} for a valid movie response" do
      set_response(200, ~s({
        "data": {
          "movie": {
            "title": "Hamlet",
            "slug": "hamlet-2025",
            "ratings": {"tmdb": 7.5, "imdb": 7.8, "rottenTomatoes": 85, "metacritic": 72},
            "awards": null,
            "cast": [],
            "crew": []
          }
        }
      }))

      assert {:ok, data} = CinegraphClient.get_movie(12345)
      assert data["title"] == "Hamlet"
      assert data["slug"] == "hamlet-2025"
      assert get_in(data, ["ratings", "tmdb"]) == 7.5
      assert get_in(data, ["ratings", "imdb"]) == 7.8
      assert get_in(data, ["ratings", "rottenTomatoes"]) == 85
      assert get_in(data, ["ratings", "metacritic"]) == 72
    end

    test "returns {:error, :not_found} when movie field is null" do
      set_response(200, ~s({"data": {"movie": null}}))
      assert {:error, :not_found} = CinegraphClient.get_movie(99999)
    end

    test "returns {:error, {:graphql_errors, errors}} on GraphQL error response" do
      set_response(200, ~s({"errors": [{"message": "Unauthorized", "locations": []}]}))

      assert {:error, {:graphql_errors, [%{"message" => "Unauthorized"}]}} =
               CinegraphClient.get_movie(12345)
    end

    test "returns {:error, {:json_decode_error, _}} for malformed JSON body" do
      set_response(200, "this is not {{ valid json }}")
      assert {:error, {:json_decode_error, _}} = CinegraphClient.get_movie(12345)
    end

    test "returns {:error, :unexpected_response} for unexpected JSON shape" do
      set_response(200, ~s({"something_unexpected": true, "no_data_key": "here"}))
      assert {:error, :unexpected_response} = CinegraphClient.get_movie(12345)
    end
  end

  # MARK: - HTTP Error Responses

  describe "get_movie/1 — non-200 HTTP responses" do
    setup do
      Application.put_env(:eventasaurus, :cinegraph,
        api_key: "test-key",
        base_url: "http://localhost:#{@port}"
      )

      :ok
    end

    test "returns {:error, {:http_error, 404}} for not-found status" do
      set_response(404, ~s({"error": "not found"}))
      assert {:error, {:http_error, 404}} = CinegraphClient.get_movie(12345)
    end

    test "returns {:error, {:http_error, 500}} for server error status" do
      set_response(500, "Internal Server Error")
      assert {:error, {:http_error, 500}} = CinegraphClient.get_movie(12345)
    end

    test "returns {:error, {:http_error, 401}} for unauthorized status" do
      set_response(401, ~s({"error": "unauthorized"}))
      assert {:error, {:http_error, 401}} = CinegraphClient.get_movie(12345)
    end
  end

  # MARK: - Network Errors

  describe "get_movie/1 — network errors" do
    test "returns {:error, {:request_failed, _}} when host is unreachable" do
      Application.put_env(:eventasaurus, :cinegraph,
        api_key: "test-key",
        base_url: "http://localhost:19876"
      )

      assert {:error, {:request_failed, _}} = CinegraphClient.get_movie(12345)
    end
  end
end
