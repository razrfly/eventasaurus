defmodule EventasaurusWeb.Live.Components.MovieAwardsComponentTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.Live.Components.MovieAwardsComponent

  defp render(assigns) do
    assigns
    |> Map.put(:__changed__, nil)
    |> MovieAwardsComponent.awards_badges()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "awards_badges/1 — nil / empty data" do
    test "renders nothing when cinegraph_data is nil" do
      assert render(%{cinegraph_data: nil}) == ""
    end

    test "renders nothing when cinegraph_data is empty map" do
      assert render(%{cinegraph_data: %{}}) == ""
    end

    test "renders nothing when awards key is null" do
      assert render(%{cinegraph_data: %{"awards" => nil}}) == ""
    end

    test "renders nothing when awards are all zero and no canonical sources" do
      html = render(%{
        cinegraph_data: %{
          "awards" => %{
            "oscarWins" => 0,
            "totalWins" => 0,
            "totalNominations" => 0,
            "summary" => nil
          },
          "canonicalSources" => %{}
        }
      })

      assert html == ""
    end
  end

  describe "awards_badges/1 — Oscar wins" do
    test "shows singular Oscar Win badge for 1 win" do
      html = render(%{
        cinegraph_data: %{"awards" => %{"oscarWins" => 1, "totalWins" => 1}}
      })

      assert html =~ "🏆"
      assert html =~ "1 Oscar Win"
      refute html =~ "Oscar Wins"
    end

    test "shows plural Oscar Wins badge for multiple wins" do
      html = render(%{
        cinegraph_data: %{"awards" => %{"oscarWins" => 4, "totalWins" => 87}}
      })

      assert html =~ "🏆"
      assert html =~ "4 Oscar Wins"
    end

    test "does not show Oscar badge when oscarWins is 0" do
      html = render(%{
        cinegraph_data: %{
          "awards" => %{"oscarWins" => 0, "totalWins" => 5, "totalNominations" => 10}
        }
      })

      refute html =~ "🏆"
      assert html =~ "5 wins"
    end
  end

  describe "awards_badges/1 — awards summary text" do
    test "uses summary string when present" do
      html = render(%{
        cinegraph_data: %{
          "awards" => %{
            "oscarWins" => 0,
            "totalWins" => 10,
            "totalNominations" => 20,
            "summary" => "11 wins & 38 nominations"
          }
        }
      })

      assert html =~ "11 wins &amp; 38 nominations"
    end

    test "builds 'X wins & Y nominations' when no summary string" do
      html = render(%{
        cinegraph_data: %{
          "awards" => %{
            "oscarWins" => 0,
            "totalWins" => 10,
            "totalNominations" => 25,
            "summary" => nil
          }
        }
      })

      assert html =~ "10 wins"
      assert html =~ "25 nominations"
    end

    test "shows only wins when totalNominations is 0" do
      html = render(%{
        cinegraph_data: %{
          "awards" => %{"oscarWins" => 0, "totalWins" => 5, "totalNominations" => 0}
        }
      })

      assert html =~ "5 wins"
      refute html =~ "nominations"
    end

    test "shows only nominations when totalWins is 0" do
      html = render(%{
        cinegraph_data: %{
          "awards" => %{"oscarWins" => 0, "totalWins" => 0, "totalNominations" => 12}
        }
      })

      assert html =~ "12 nominations"
      refute html =~ "wins"
    end
  end

  describe "awards_badges/1 — canonical source badges" do
    test "renders 1001 Movies badge" do
      html = render(%{cinegraph_data: %{"canonicalSources" => %{"1001_movies" => true}}})
      assert html =~ "1001 Movies"
      assert html =~ "📚"
    end

    test "renders Criterion badge" do
      html = render(%{cinegraph_data: %{"canonicalSources" => %{"criterion" => true}}})
      assert html =~ "Criterion"
      assert html =~ "🎞"
    end

    test "renders Sight &amp; Sound badge" do
      html = render(%{cinegraph_data: %{"canonicalSources" => %{"sight_and_sound" => true}}})
      assert html =~ "Sight"
      assert html =~ "Sound"
      assert html =~ "👁"
    end

    test "renders BFI badge" do
      html = render(%{cinegraph_data: %{"canonicalSources" => %{"bfi" => true}}})
      assert html =~ "BFI"
      assert html =~ "🎭"
    end

    test "renders AFI badge" do
      html = render(%{cinegraph_data: %{"canonicalSources" => %{"afi" => true}}})
      assert html =~ "AFI"
      assert html =~ "🎥"
    end

    test "does not render badge for false canonical source" do
      html = render(%{cinegraph_data: %{"canonicalSources" => %{"criterion" => false}}})
      assert html == ""
    end

    test "does not render badge for unknown canonical source key" do
      html = render(%{
        cinegraph_data: %{"canonicalSources" => %{"some_unknown_list" => true}}
      })

      refute html =~ "some_unknown_list"
    end

    test "renders multiple badges sorted by priority" do
      html = render(%{
        cinegraph_data: %{
          "canonicalSources" => %{
            "afi" => true,
            "1001_movies" => true,
            "criterion" => true
          }
        }
      })

      assert html =~ "1001 Movies"
      assert html =~ "Criterion"
      assert html =~ "AFI"

      # 1001 Movies (priority 1) should appear before AFI (priority 5)
      {pos_1001, _} = :binary.match(html, "1001 Movies")
      {pos_afi, _} = :binary.match(html, "AFI")
      assert pos_1001 < pos_afi
    end
  end

  describe "awards_badges/1 — combined data" do
    test "renders Oscar badge and summary together" do
      html = render(%{
        cinegraph_data: %{
          "awards" => %{
            "oscarWins" => 4,
            "totalWins" => 87,
            "totalNominations" => 121,
            "summary" => "Won 4 Oscars including Best Picture"
          }
        }
      })

      assert html =~ "4 Oscar Wins"
      assert html =~ "Won 4 Oscars including Best Picture"
    end
  end
end
