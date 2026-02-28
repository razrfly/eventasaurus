defmodule EventasaurusWeb.Live.Components.MovieRatingsComponentTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.Live.Components.MovieRatingsComponent

  defp render(assigns) do
    assigns
    |> Map.put(:__changed__, nil)
    |> MovieRatingsComponent.ratings_panel()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "ratings_panel/1 — nil data" do
    test "renders nothing when cinegraph_data and tmdb_rating are both nil" do
      html = render(%{cinegraph_data: nil, tmdb_rating: nil})
      assert html == ""
    end

    test "renders nothing when cinegraph_data is nil and tmdb_rating is nil" do
      html = render(%{cinegraph_data: %{}, tmdb_rating: nil})
      assert html == ""
    end
  end

  describe "ratings_panel/1 — fallback to tmdb_rating" do
    test "shows TMDB badge using tmdb_rating when cinegraph_data has no ratings" do
      html = render(%{cinegraph_data: nil, tmdb_rating: 7.3})
      assert html =~ "TMDB"
      assert html =~ "7.3"
    end

    test "prefers cinegraph tmdb score over tmdb_rating fallback" do
      html = render(%{
        cinegraph_data: %{"ratings" => %{"tmdb" => 8.5}},
        tmdb_rating: 6.0
      })
      assert html =~ "8.5"
      refute html =~ "6.0"
    end
  end

  describe "ratings_panel/1 — all four sources" do
    test "renders all four source badges when fully populated" do
      html = render(%{
        cinegraph_data: %{
          "ratings" => %{
            "tmdb" => 7.5,
            "imdb" => 7.8,
            "rottenTomatoes" => 85,
            "metacritic" => 72
          }
        },
        tmdb_rating: nil
      })

      assert html =~ "TMDB"
      assert html =~ "7.5"
      assert html =~ "IMDb"
      assert html =~ "7.8"
      assert html =~ "RT"
      assert html =~ "85%"
      assert html =~ "Metacritic"
      assert html =~ "72"
    end
  end

  describe "ratings_panel/1 — partial scores" do
    test "renders only available badges when some scores are nil" do
      html = render(%{
        cinegraph_data: %{
          "ratings" => %{
            "tmdb" => 6.9,
            "imdb" => nil,
            "rottenTomatoes" => nil,
            "metacritic" => 55
          }
        },
        tmdb_rating: nil
      })

      assert html =~ "TMDB"
      assert html =~ "6.9"
      assert html =~ "Metacritic"
      assert html =~ "55"
      refute html =~ "IMDb"
      refute html =~ "RT"
    end

    test "renders nothing when all cinegraph scores are nil and no tmdb_rating" do
      html = render(%{
        cinegraph_data: %{
          "ratings" => %{
            "tmdb" => nil,
            "imdb" => nil,
            "rottenTomatoes" => nil,
            "metacritic" => nil
          }
        },
        tmdb_rating: nil
      })

      assert html == ""
    end
  end

  describe "ratings_panel/1 — Rotten Tomatoes color coding" do
    test "applies green class for score >= 75" do
      html = render(%{cinegraph_data: %{"ratings" => %{"rottenTomatoes" => 80}}, tmdb_rating: nil})
      assert html =~ "green"
    end

    test "applies lime class for score >= 60 and < 75" do
      html = render(%{cinegraph_data: %{"ratings" => %{"rottenTomatoes" => 65}}, tmdb_rating: nil})
      assert html =~ "lime"
    end

    test "applies red class for score < 60" do
      html = render(%{cinegraph_data: %{"ratings" => %{"rottenTomatoes" => 45}}, tmdb_rating: nil})
      assert html =~ "red"
    end

    test "shows tomato icon for score >= 60" do
      html = render(%{cinegraph_data: %{"ratings" => %{"rottenTomatoes" => 75}}, tmdb_rating: nil})
      assert html =~ "🍅"
    end

    test "shows splat icon for score < 60" do
      html = render(%{cinegraph_data: %{"ratings" => %{"rottenTomatoes" => 30}}, tmdb_rating: nil})
      assert html =~ "🦠"
    end
  end

  describe "ratings_panel/1 — Metacritic color coding" do
    test "applies green class for score >= 61" do
      html = render(%{cinegraph_data: %{"ratings" => %{"metacritic" => 80}}, tmdb_rating: nil})
      assert html =~ "green"
    end

    test "applies yellow class for score >= 40 and < 61" do
      html = render(%{cinegraph_data: %{"ratings" => %{"metacritic" => 50}}, tmdb_rating: nil})
      assert html =~ "yellow"
    end

    test "applies red class for score < 40" do
      html = render(%{cinegraph_data: %{"ratings" => %{"metacritic" => 25}}, tmdb_rating: nil})
      assert html =~ "red"
    end
  end

  describe "ratings_panel/1 — score formatting" do
    test "formats TMDB score to one decimal place" do
      html = render(%{cinegraph_data: %{"ratings" => %{"tmdb" => 7.0}}, tmdb_rating: nil})
      assert html =~ "7.0"
    end

    test "formats IMDb score to one decimal place" do
      html = render(%{cinegraph_data: %{"ratings" => %{"imdb" => 8.0}}, tmdb_rating: nil})
      assert html =~ "8.0"
    end

    test "appends % to Rotten Tomatoes score" do
      html = render(%{cinegraph_data: %{"ratings" => %{"rottenTomatoes" => 92}}, tmdb_rating: nil})
      assert html =~ "92%"
    end
  end
end
