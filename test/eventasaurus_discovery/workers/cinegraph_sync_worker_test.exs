defmodule CinegraphWorkerTestPlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    {status, body} = Agent.get(:cinegraph_worker_test_response, & &1)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end
end

defmodule EventasaurusDiscovery.Workers.CinegraphSyncWorkerTest do
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusDiscovery.Workers.CinegraphSyncWorker
  alias EventasaurusDiscovery.Movies.{Movie, MovieStore}
  alias EventasaurusApp.Repo

  @port 18_235

  setup_all do
    {:ok, _} = Agent.start_link(fn -> {200, ""} end, name: :cinegraph_worker_test_response)
    {:ok, _} = Plug.Cowboy.http(CinegraphWorkerTestPlug, [], port: @port)

    on_exit(fn ->
      Plug.Cowboy.shutdown(CinegraphWorkerTestPlug.HTTP)
      Agent.stop(:cinegraph_worker_test_response)
    end)

    :ok
  end

  setup do
    original = Application.get_env(:eventasaurus, :cinegraph, [])
    on_exit(fn -> Application.put_env(:eventasaurus, :cinegraph, original) end)
    :ok
  end

  defp set_response(status, body),
    do: Agent.update(:cinegraph_worker_test_response, fn _ -> {status, body} end)

  defp use_test_server do
    Application.put_env(:eventasaurus, :cinegraph,
      api_key: "test-key",
      base_url: "http://localhost:#{@port}"
    )
  end

  defp perform(args), do: CinegraphSyncWorker.perform(%Oban.Job{args: args})

  # MovieStore.create_movie/1 runs the changeset that auto-generates the slug.
  defp create_movie(attrs \\ %{}) do
    defaults = %{
      tmdb_id: :erlang.unique_integer([:positive]),
      title: "Test Movie #{:erlang.unique_integer([:positive])}"
    }

    {:ok, movie} = MovieStore.create_movie(Map.merge(defaults, attrs))
    movie
  end

  # MARK: - Single Movie Mode

  describe "perform/1 — single movie mode" do
    test "returns {:ok, :missing} for an unknown or deleted movie_id" do
      assert {:ok, :missing} = perform(%{"movie_id" => 999_999_999})
    end

    test "syncs data and stamps cinegraph_synced_at on success" do
      use_test_server()

      movie = create_movie()

      set_response(200, ~s({
        "data": {
          "movie": {
            "title": "Test Movie",
            "slug": "test-movie-#{movie.tmdb_id}",
            "ratings": {"tmdb": 7.2, "imdb": 7.5, "rottenTomatoes": 90, "metacritic": 80},
            "awards": {"oscarWins": 2, "totalWins": 15, "totalNominations": 30, "summary": null},
            "cast": [{"character": "Hero", "castOrder": 0, "person": {"name": "Test Actor", "profilePath": null, "slug": "test-actor"}}],
            "crew": [{"job": "Director", "department": "Directing", "person": {"name": "Test Director", "profilePath": null, "slug": "test-director"}}],
            "canonicalSources": {}
          }
        }
      }))

      assert {:ok, :synced} = perform(%{"movie_id" => movie.id})

      updated = Repo.get!(Movie, movie.id)
      assert updated.cinegraph_synced_at != nil
      assert updated.cinegraph_data != nil
      assert get_in(updated.cinegraph_data, ["ratings", "tmdb"]) == 7.2
      assert get_in(updated.cinegraph_data, ["awards", "oscarWins"]) == 2
    end

    test "stamps cinegraph_synced_at without data when movie is not found in Cinegraph" do
      use_test_server()

      movie = create_movie()
      set_response(200, ~s({"data": {"movie": null}}))

      assert {:ok, :not_found} = perform(%{"movie_id" => movie.id})

      updated = Repo.get!(Movie, movie.id)
      assert updated.cinegraph_synced_at != nil
      assert updated.cinegraph_data == nil
    end

    test "returns {:error, :cinegraph_unavailable} and preserves existing data when API is down" do
      # Simulate API being down by removing the API key
      Application.put_env(:eventasaurus, :cinegraph, api_key: nil)

      movie = create_movie()

      existing_data = %{"ratings" => %{"tmdb" => 8.0}, "slug" => "existing"}

      movie
      |> Movie.cinegraph_changeset(%{cinegraph_data: existing_data})
      |> Repo.update!()

      assert {:error, :cinegraph_unavailable} = perform(%{"movie_id" => movie.id})

      updated = Repo.get!(Movie, movie.id)
      assert updated.cinegraph_data == existing_data
    end

    test "returns {:error, :cinegraph_unavailable} on HTTP 500 without modifying existing data" do
      use_test_server()

      movie = create_movie()

      existing_data = %{"ratings" => %{"imdb" => 7.5}, "slug" => "keep-me"}

      movie
      |> Movie.cinegraph_changeset(%{cinegraph_data: existing_data})
      |> Repo.update!()

      set_response(500, "Internal Server Error")

      assert {:error, :cinegraph_unavailable} = perform(%{"movie_id" => movie.id})

      updated = Repo.get!(Movie, movie.id)
      assert updated.cinegraph_data == existing_data
    end
  end

  # MARK: - Sweep Mode

  describe "perform/1 — sweep mode" do
    test "enqueues individual jobs for movies needing sync" do
      _movie1 = create_movie()
      _movie2 = create_movie()

      # Both movies have nil cinegraph_synced_at — both should be picked up
      assert {:ok, %{enqueued: count}} = perform(%{"sweep" => true})
      assert count >= 2
    end

    test "skips movies with a recent cinegraph_synced_at" do
      recently_synced = create_movie()
      _unsynced = create_movie()

      recently_synced
      |> Movie.cinegraph_changeset(%{
        cinegraph_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      # With exactly 2 movies in the sandbox — 1 recently synced, 1 not —
      # the sweep should enqueue only 1 job.
      assert {:ok, %{enqueued: 1}} = perform(%{"sweep" => true})
    end
  end
end
