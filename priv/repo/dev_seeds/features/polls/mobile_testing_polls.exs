# ============================================================================
# Phase V: Mobile Testing Comprehensive Polls
# ============================================================================
#
# Purpose:
#   Creates comprehensive polling test data covering ALL combinations of
#   poll types and voting systems for mobile testing and debugging.
#
# Coverage:
#   - 9 Poll Types: movie, cocktail, music_track, places, venue, time,
#                   date_selection, general, custom
#   - 4 Voting Systems: binary, approval, ranked, star
#   - Total: 36 polls across 9 events (4 polls per event)
#
# Slugs:
#   Fixed slugs for stable URLs across re-seeds:
#   - poll-test-{type}
#   - Examples: poll-test-movies, poll-test-cocktails, poll-test-music
#
# Documentation:
#   See priv/repo/dev_seeds/POLLING_TEST_DATA.md for quick reference URLs
#
# ============================================================================

# Load helpers if running independently
unless Code.ensure_loaded?(DevSeeds.Helpers) do
  Code.require_file("../../support/helpers.exs", __DIR__)
end

defmodule MobileTestingPolls do
  import Ecto.Query
  alias EventasaurusApp.{Repo, Events, Accounts, Groups, Venues}
  alias EventasaurusWeb.Services.RichDataManager
  alias DevSeeds.Helpers

  IO.puts("📦 MobileTestingPolls module loaded")

  @doc """
  Creates comprehensive polling test data for mobile testing.
  All events use explicit slugs for stable URLs.
  Creates 9 events with 4 polls each (36 polls total).
  """
  def run do
    IO.puts("🚀 MobileTestingPolls.run() called")
    Helpers.section("Creating Phase V: Mobile Testing Comprehensive Polls")

    users = get_available_users()
    groups = get_available_groups()
    venues = get_available_venues()

    if length(users) < 10 do
      Helpers.error("Not enough users available. Need at least 10 users.")
      nil
    else
      # Create 9 test events (one per poll type), each with 4 polls
      create_movie_polls_event(users, groups, venues)
      create_cocktail_polls_event(users, groups, venues)
      create_music_polls_event(users, groups, venues)
      create_places_polls_event(users, groups, venues)
      create_venue_polls_event(users, groups, venues)
      create_time_polls_event(users, groups, venues)
      create_date_polls_event(users, groups, venues)
      create_general_polls_event(users, groups, venues)
      create_custom_polls_event(users, groups, venues)

      Helpers.success("Phase V: Created 9 events with 36 polls total!")
    end
  end

  # ============================================================================
  # Event Creation Functions
  # ============================================================================

  defp create_movie_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "Movie Night - Poll Testing",
      description: "Comprehensive movie poll testing across all voting systems",
      slug: "poll-test-movies",
      event_type: "social",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(7, :day),
      end_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(3, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        # Add organizer as participant
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        # Add 12 participants
        participants = add_participants(event, users, 12)

        # Create 4 polls (one for each voting system)
        create_movie_binary_poll(event, participants, organizer.id)
        create_movie_approval_poll(event, participants, organizer.id)
        create_movie_ranked_poll(event, participants, organizer.id)
        create_movie_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create movie event: #{inspect(changeset.errors)}")
    end
  end

  defp create_cocktail_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "Cocktail Happy Hour - Poll Testing",
      description: "Comprehensive cocktail poll testing across all voting systems",
      slug: "poll-test-cocktails",
      event_type: "social",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(8, :day),
      end_at: DateTime.utc_now() |> DateTime.add(8, :day) |> DateTime.add(3, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        participants = add_participants(event, users, 12)

        create_cocktail_binary_poll(event, participants, organizer.id)
        create_cocktail_approval_poll(event, participants, organizer.id)
        create_cocktail_ranked_poll(event, participants, organizer.id)
        create_cocktail_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create cocktail event: #{inspect(changeset.errors)}")
    end
  end

  defp create_music_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "Music Festival - Poll Testing",
      description: "Comprehensive music poll testing across all voting systems",
      slug: "poll-test-music",
      event_type: "concert",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(9, :day),
      end_at: DateTime.utc_now() |> DateTime.add(9, :day) |> DateTime.add(6, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        participants = add_participants(event, users, 12)

        create_music_binary_poll(event, participants, organizer.id)
        create_music_approval_poll(event, participants, organizer.id)
        create_music_ranked_poll(event, participants, organizer.id)
        create_music_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create music event: #{inspect(changeset.errors)}")
    end
  end

  defp create_places_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "Restaurant Week - Poll Testing",
      description: "Comprehensive restaurant poll testing across all voting systems",
      slug: "poll-test-places",
      event_type: "dining",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(10, :day),
      end_at: DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.add(2, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        participants = add_participants(event, users, 12)

        create_places_binary_poll(event, participants, organizer.id)
        create_places_approval_poll(event, participants, organizer.id)
        create_places_ranked_poll(event, participants, organizer.id)
        create_places_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create places event: #{inspect(changeset.errors)}")
    end
  end

  defp create_venue_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "Venue Selection - Poll Testing",
      description: "Comprehensive venue poll testing across all voting systems",
      slug: "poll-test-venues",
      event_type: "planning",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(11, :day),
      end_at: DateTime.utc_now() |> DateTime.add(11, :day) |> DateTime.add(4, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        participants = add_participants(event, users, 12)

        create_venue_binary_poll(event, participants, organizer.id)
        create_venue_approval_poll(event, participants, organizer.id)
        create_venue_ranked_poll(event, participants, organizer.id)
        create_venue_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create venue event: #{inspect(changeset.errors)}")
    end
  end

  defp create_time_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "Workshop Scheduling - Poll Testing",
      description: "Comprehensive time poll testing across all voting systems",
      slug: "poll-test-times",
      event_type: "workshop",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(12, :day),
      end_at: DateTime.utc_now() |> DateTime.add(12, :day) |> DateTime.add(3, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        participants = add_participants(event, users, 12)

        create_time_binary_poll(event, participants, organizer.id)
        create_time_approval_poll(event, participants, organizer.id)
        create_time_ranked_poll(event, participants, organizer.id)
        create_time_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create time event: #{inspect(changeset.errors)}")
    end
  end

  defp create_date_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "Event Date Planning - Poll Testing",
      description: "Comprehensive date poll testing across all voting systems",
      slug: "poll-test-dates",
      event_type: "planning",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(13, :day),
      end_at: DateTime.utc_now() |> DateTime.add(13, :day) |> DateTime.add(2, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        participants = add_participants(event, users, 12)

        create_date_binary_poll(event, participants, organizer.id)
        create_date_approval_poll(event, participants, organizer.id)
        create_date_ranked_poll(event, participants, organizer.id)
        create_date_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create date event: #{inspect(changeset.errors)}")
    end
  end

  defp create_general_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "General Decisions - Poll Testing",
      description: "Comprehensive general poll testing across all voting systems",
      slug: "poll-test-general",
      event_type: "planning",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(14, :day),
      end_at: DateTime.utc_now() |> DateTime.add(14, :day) |> DateTime.add(3, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        participants = add_participants(event, users, 12)

        create_general_binary_poll(event, participants, organizer.id)
        create_general_approval_poll(event, participants, organizer.id)
        create_general_ranked_poll(event, participants, organizer.id)
        create_general_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create general event: #{inspect(changeset.errors)}")
    end
  end

  defp create_custom_polls_event(users, groups, venues) do
    organizer = Enum.random(users)
    group = Enum.random(groups)
    venue = Enum.random(venues)

    event_attrs = %{
      title: "Custom Options - Poll Testing",
      description: "Comprehensive custom poll testing across all voting systems",
      slug: "poll-test-custom",
      event_type: "planning",
      status: "polling",
      user_id: organizer.id,
      group_id: group.id,
      venue_id: venue.id,
      start_at: DateTime.utc_now() |> DateTime.add(15, :day),
      end_at: DateTime.utc_now() |> DateTime.add(15, :day) |> DateTime.add(3, :hour),
      timezone: "America/Los_Angeles",
      polling_deadline: DateTime.utc_now() |> DateTime.add(5, :day),
      is_private: false
    }

    case Events.create_event(event_attrs) do
      {:ok, event} ->
        IO.puts("✓ Created event: #{event.title} (#{event.slug})")

        Events.create_event_participant(%{
          event_id: event.id,
          user_id: organizer.id,
          status: "confirmed",
          role: "organizer"
        })

        participants = add_participants(event, users, 12)

        create_custom_binary_poll(event, participants, organizer.id)
        create_custom_approval_poll(event, participants, organizer.id)
        create_custom_ranked_poll(event, participants, organizer.id)
        create_custom_star_poll(event, participants, organizer.id)

      {:error, changeset} ->
        Helpers.error("Failed to create custom event: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Movie Polls
  # ============================================================================

  defp create_movie_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "movie",
      voting_system: "binary",
      title: "Movie Selection - Yes/No Voting",
      description: "Vote yes/no on these movie options",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary movie poll")

        # Phase VI: Fetch real movie data from TMDB API
        search_queries = ["The Shawshank Redemption", "The Godfather", "The Dark Knight", "Pulp Fiction"]
        options = Enum.map(search_queries, &fetch_movie_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary movie poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_movie_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "movie",
      voting_system: "approval",
      title: "Movie Selection - Approval Voting",
      description: "Select all movies you'd be happy to watch (up to 2)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 2,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval movie poll")

        # Phase VI: Fetch real movie data from TMDB API
        search_queries = ["Inception", "Forrest Gump", "The Matrix", "Goodfellas"]
        options = Enum.map(search_queries, &fetch_movie_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval movie poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_movie_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "movie",
      voting_system: "ranked",
      title: "Movie Selection - Ranked Choice",
      description: "Rank these movies in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked movie poll")

        # Phase VI: Fetch real movie data from TMDB API
        search_queries = ["Parasite", "Spirited Away", "Interstellar", "The Prestige"]
        options = Enum.map(search_queries, &fetch_movie_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked movie poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_movie_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "movie",
      voting_system: "star",
      title: "Movie Selection - Star Rating",
      description: "Rate each movie from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star movie poll")

        # Phase VI: Fetch real movie data from TMDB API
        search_queries = ["Whiplash", "La La Land", "Everything Everywhere All at Once", "The Grand Budapest Hotel"]
        options = Enum.map(search_queries, &fetch_movie_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star movie poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Cocktail Polls
  # ============================================================================

  defp create_cocktail_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "cocktail",
      voting_system: "binary",
      title: "Cocktail Selection - Yes/No Voting",
      description: "Vote yes/no on these cocktail options",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary cocktail poll")

        # Phase VI: Fetch real cocktail data from CocktailDB API
        search_queries = ["Margarita", "Mojito", "Old Fashioned"]
        options = Enum.map(search_queries, &fetch_cocktail_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary cocktail poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_cocktail_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "cocktail",
      voting_system: "approval",
      title: "Cocktail Selection - Approval Voting",
      description: "Select all cocktails you'd enjoy (up to 3)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 3,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval cocktail poll")

        # Phase VI: Fetch real cocktail data from CocktailDB API
        search_queries = ["Cosmopolitan", "Piña Colada", "Mai Tai"]
        options = Enum.map(search_queries, &fetch_cocktail_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval cocktail poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_cocktail_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "cocktail",
      voting_system: "ranked",
      title: "Cocktail Selection - Ranked Choice",
      description: "Rank these cocktails in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked cocktail poll")

        # Phase VI: Fetch real cocktail data from CocktailDB API
        search_queries = ["Whiskey Sour", "Negroni", "Manhattan"]
        options = Enum.map(search_queries, &fetch_cocktail_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked cocktail poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_cocktail_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "cocktail",
      voting_system: "star",
      title: "Cocktail Selection - Star Rating",
      description: "Rate each cocktail from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star cocktail poll")

        # Phase VI: Fetch real cocktail data from CocktailDB API
        search_queries = ["Aperol Spritz", "Espresso Martini", "French 75"]
        options = Enum.map(search_queries, &fetch_cocktail_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star cocktail poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Music Polls
  # ============================================================================

  defp create_music_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "music_track",
      voting_system: "binary",
      title: "Opening Set - Yes/No Voting",
      description: "Vote yes/no on these opening tracks",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary music poll")

        # Phase VI: Fetch real music data from Spotify API
        search_queries = ["Billie Jean Michael Jackson", "Bohemian Rhapsody Queen", "Superstition Stevie Wonder", "Don't Stop Believin' Journey"]
        options = Enum.map(search_queries, &fetch_music_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary music poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_music_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "music_track",
      voting_system: "approval",
      title: "Festival Headliner - Approval Voting",
      description: "Select all tracks you'd enjoy (up to 3)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 3,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval music poll")

        # Phase VI: Fetch real music data from Spotify API
        search_queries = ["Blinding Lights The Weeknd", "Rolling in the Deep Adele", "Uptown Funk Mark Ronson Bruno Mars", "Mr. Brightside The Killers"]
        options = Enum.map(search_queries, &fetch_music_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval music poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_music_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "music_track",
      voting_system: "ranked",
      title: "Encore Set - Ranked Choice",
      description: "Rank these encore tracks in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked music poll")

        # Phase VI: Fetch real music data from Spotify API
        search_queries = ["Sweet Child O' Mine Guns N' Roses", "September Earth Wind Fire", "Livin' on a Prayer Bon Jovi", "I Wanna Dance with Somebody Whitney Houston"]
        options = Enum.map(search_queries, &fetch_music_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked music poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_music_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "music_track",
      voting_system: "star",
      title: "Acoustic Set - Star Rating",
      description: "Rate each acoustic track from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star music poll")

        # Phase VI: Fetch real music data from Spotify API
        search_queries = ["Wonderwall Oasis", "Fast Car Tracy Chapman", "Hallelujah Jeff Buckley", "Tears in Heaven Eric Clapton"]
        options = Enum.map(search_queries, &fetch_music_option/1)

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            image_url: opt[:image_url],
            metadata: opt[:metadata],
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star music poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Places (Restaurant) Polls
  # ============================================================================

  defp create_places_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "places",
      voting_system: "binary",
      title: "Restaurant Selection - Yes/No Voting",
      description: "Vote yes/no on these restaurant options",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary places poll")

        options = [
          %{title: "Mario's Italian Kitchen", description: "Authentic Italian cuisine"},
          %{title: "Sakura Sushi Bar", description: "Fresh sushi and sashimi"},
          %{title: "The Steakhouse", description: "Premium aged beef"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary places poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_places_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "places",
      voting_system: "approval",
      title: "Restaurant Selection - Approval Voting",
      description: "Select all restaurants you'd enjoy (up to 2)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 2,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval places poll")

        options = [
          %{title: "Taco Fiesta", description: "Mexican street food"},
          %{title: "Green Garden Bistro", description: "Farm-to-table vegetarian"},
          %{title: "Thai Spice Kitchen", description: "Authentic Thai flavors"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval places poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_places_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "places",
      voting_system: "ranked",
      title: "Restaurant Selection - Ranked Choice",
      description: "Rank these restaurants in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked places poll")

        options = [
          %{title: "Le Petit Bistro", description: "Classic French cuisine"},
          %{title: "Seoul Kitchen", description: "Korean BBQ and banchan"},
          %{title: "The Burger Joint", description: "Gourmet burgers and shakes"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked places poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_places_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "places",
      voting_system: "star",
      title: "Restaurant Selection - Star Rating",
      description: "Rate each restaurant from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star places poll")

        options = [
          %{title: "Bella Vista", description: "Mediterranean seafood"},
          %{title: "Ramen House", description: "Traditional Japanese ramen"},
          %{title: "BBQ Brothers", description: "Slow-smoked Texas BBQ"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star places poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Venue Polls
  # ============================================================================

  defp create_venue_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "venue",
      voting_system: "binary",
      title: "Conference Venue - Yes/No Voting",
      description: "Vote yes/no on these venue options",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary venue poll")

        options = [
          %{title: "Downtown Convention Center", description: "Modern facilities, 500 capacity"},
          %{title: "Riverside Hotel & Conference", description: "Waterfront views, 300 capacity"},
          %{title: "Tech Hub Meeting Space", description: "High-tech setup, 200 capacity"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary venue poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_venue_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "venue",
      voting_system: "approval",
      title: "Wedding Venue - Approval Voting",
      description: "Select all venues you'd approve (up to 2)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 2,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval venue poll")

        options = [
          %{title: "Garden Estate", description: "Outdoor ceremony, 150 guests"},
          %{title: "Historic Manor", description: "Indoor elegance, 200 guests"},
          %{title: "Beachside Resort", description: "Ocean views, 175 guests"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval venue poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_venue_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "venue",
      voting_system: "ranked",
      title: "Corporate Retreat - Ranked Choice",
      description: "Rank these retreat venues in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked venue poll")

        options = [
          %{title: "Mountain Lodge", description: "Scenic views, team building activities"},
          %{title: "Urban Hotel", description: "City center, modern amenities"},
          %{title: "Lakeside Resort", description: "Peaceful setting, water sports"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked venue poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_venue_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "venue",
      voting_system: "star",
      title: "Art Exhibition - Star Rating",
      description: "Rate each gallery venue from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star venue poll")

        options = [
          %{title: "Contemporary Gallery", description: "Modern space, natural lighting"},
          %{title: "Historic Museum", description: "Classic architecture, established"},
          %{title: "Warehouse Loft", description: "Industrial chic, flexible layout"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star venue poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Time Polls
  # ============================================================================

  defp create_time_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "time",
      voting_system: "binary",
      title: "Workshop Time - Yes/No Voting",
      description: "Vote yes/no on these time slots",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary time poll")

        options = [
          %{title: "Morning Session (9-12 AM)", description: "Early start, fresh minds"},
          %{title: "Afternoon (2-5 PM)", description: "Post-lunch session"},
          %{title: "Evening (6-9 PM)", description: "After work hours"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary time poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_time_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "time",
      voting_system: "approval",
      title: "Meeting Time - Approval Voting",
      description: "Select all times that work for you (up to 2)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 2,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval time poll")

        options = [
          %{title: "Monday 10 AM", description: "Start of week"},
          %{title: "Wednesday 2 PM", description: "Mid-week afternoon"},
          %{title: "Friday 4 PM", description: "End of week"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval time poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_time_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "time",
      voting_system: "ranked",
      title: "Class Schedule - Ranked Choice",
      description: "Rank these class schedules in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked time poll")

        options = [
          %{title: "Tue/Thu 9 AM", description: "2 days per week, morning"},
          %{title: "Mon/Wed/Fri 1 PM", description: "3 days per week, afternoon"},
          %{title: "Saturday 10 AM-2 PM", description: "Weekend intensive"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked time poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_time_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "time",
      voting_system: "star",
      title: "Practice Time - Star Rating",
      description: "Rate each practice time from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star time poll")

        options = [
          %{title: "Early Bird (6-7:30 AM)", description: "Morning energy"},
          %{title: "Lunch Break (12-1 PM)", description: "Mid-day session"},
          %{title: "Evening (7-8:30 PM)", description: "After work"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star time poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Date Polls
  # ============================================================================

  defp create_date_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "date_selection",
      voting_system: "binary",
      title: "Event Date - Yes/No Voting",
      description: "Vote yes/no on these date options",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary date poll")

        options = [
          %{title: "March 15, 2025", description: "Mid-March option"},
          %{title: "March 21, 2025", description: "Spring equinox"},
          %{title: "March 30, 2025", description: "End of March"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary date poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_date_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "date_selection",
      voting_system: "approval",
      title: "Meetup Date - Approval Voting",
      description: "Select all dates that work for you (up to 2)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 2,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval date poll")

        options = [
          %{title: "April 10, 2025", description: "Early April"},
          %{title: "April 12, 2025", description: "Mid-April"},
          %{title: "April 15, 2025", description: "Tax day!"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval date poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_date_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "date_selection",
      voting_system: "ranked",
      title: "Retreat Date - Ranked Choice",
      description: "Rank these retreat date ranges in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked date poll")

        options = [
          %{title: "June 5-7, 2025", description: "Early June weekend"},
          %{title: "June 12-14, 2025", description: "Mid-June weekend"},
          %{title: "June 19-21, 2025", description: "Late June weekend"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked date poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_date_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "date_selection",
      voting_system: "star",
      title: "Launch Date - Star Rating",
      description: "Rate each potential launch date from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star date poll")

        options = [
          %{title: "May 5, 2025", description: "Cinco de Mayo"},
          %{title: "May 14, 2025", description: "Mid-month"},
          %{title: "May 23, 2025", description: "Memorial Day weekend"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star date poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # General Polls
  # ============================================================================

  defp create_general_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "general",
      voting_system: "binary",
      title: "Event Activities - Yes/No Voting",
      description: "Vote yes/no on these activity options",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary general poll")

        options = [
          %{title: "Team Building Games", description: "Interactive group activities"},
          %{title: "Networking Session", description: "Structured mingling time"},
          %{title: "Guest Speaker", description: "Industry expert presentation"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary general poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_general_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "general",
      voting_system: "approval",
      title: "Event Format - Approval Voting",
      description: "Select all formats you'd approve (up to 2)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 2,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval general poll")

        options = [
          %{title: "In-Person Only", description: "Traditional face-to-face event"},
          %{title: "Hybrid Event", description: "Mix of in-person and virtual"},
          %{title: "Fully Virtual", description: "Online-only event"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval general poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_general_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "general",
      voting_system: "ranked",
      title: "Event Theme - Ranked Choice",
      description: "Rank these themes in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked general poll")

        options = [
          %{title: "Tropical Paradise", description: "Beach and island vibes"},
          %{title: "Masquerade Ball", description: "Elegant mystery theme"},
          %{title: "Casino Night", description: "Vegas-style gaming"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked general poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_general_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "general",
      voting_system: "star",
      title: "Event Features - Star Rating",
      description: "Rate each feature from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star general poll")

        options = [
          %{title: "Live Entertainment", description: "Band or DJ performance"},
          %{title: "Photo Booth", description: "Professional photo setup"},
          %{title: "Premium Catering", description: "Upscale food and drinks"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star general poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Custom Polls
  # ============================================================================

  defp create_custom_binary_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "custom",
      voting_system: "binary",
      title: "Project Priorities - Yes/No Voting",
      description: "Vote yes/no on these project priorities",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "allow_maybe" => true,
        "require_all_votes" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created binary custom poll")

        options = [
          %{title: "Feature Development", description: "New capabilities and functions"},
          %{title: "Bug Fixes", description: "Address existing issues"},
          %{title: "Performance Optimization", description: "Speed and efficiency"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create binary custom poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_custom_approval_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "custom",
      voting_system: "approval",
      title: "Team Initiatives - Approval Voting",
      description: "Select all initiatives you'd approve (up to 3)",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_selections" => 3,
        "min_selections" => 1
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created approval custom poll")

        options = [
          %{title: "Mentorship Program", description: "Pair experienced with new members"},
          %{title: "Learning Budget", description: "Funds for courses and conferences"},
          %{title: "Flex Time Policy", description: "Flexible work hours"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create approval custom poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_custom_ranked_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "custom",
      voting_system: "ranked",
      title: "Office Perks - Ranked Choice",
      description: "Rank these office perks in order of preference",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "require_full_ranking" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created ranked custom poll")

        options = [
          %{title: "Remote Work", description: "Work from anywhere option"},
          %{title: "Gym Membership", description: "Health club access"},
          %{title: "Free Lunch", description: "Catered daily meals"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create ranked custom poll: #{inspect(changeset.errors)}")
    end
  end

  defp create_custom_star_poll(event, participants, organizer_id) do
    poll_attrs = %{
      event_id: event.id,
      poll_type: "custom",
      voting_system: "star",
      title: "Tool Preferences - Star Rating",
      description: "Rate each tool category from 1-5 stars",
      phase: "voting",
      visibility: "public",
    created_by_id: organizer_id,
      settings: %{
        "max_stars" => 5,
        "allow_half_stars" => false
      }
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        IO.puts("  ✓ Created star custom poll")

        options = [
          %{title: "Project Management Software", description: "Task tracking and planning"},
          %{title: "Communication Platform", description: "Team messaging and calls"},
          %{title: "Design Tools", description: "Creative and design software"}
        ]

        Enum.each(options, fn opt ->
          Events.create_poll_option(%{
            poll_id: poll.id,
            title: opt.title,
            description: opt.description,
            suggested_by_id: organizer_id
          })
        end)

        add_sample_votes(poll, participants, 8)

      {:error, changeset} ->
        IO.puts("  ✗ Failed to create star custom poll: #{inspect(changeset.errors)}")
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp get_available_users do
    # Query users directly without soft-delete filtering (users table doesn't have deleted_at)
    Repo.all(from u in "users", limit: 50, select: %{
      id: u.id,
      email: u.email,
      name: u.name
    })
    |> Enum.map(fn user_data ->
      %Accounts.User{
        id: user_data.id,
        email: user_data.email,
        name: user_data.name
      }
    end)
  end

  defp get_available_groups do
    Repo.all(from g in Groups.Group, where: is_nil(g.deleted_at), limit: 20, select: g)
  end

  defp get_available_venues do
    Repo.all(from v in Venues.Venue, limit: 20, select: v)
  end

  defp add_participants(event, users, count) do
    # Get random users excluding those already participating
    existing_participant_ids =
      Repo.all(
        from ep in Events.EventParticipant,
        where: ep.event_id == ^event.id,
        select: ep.user_id
      )

    available_users = Enum.reject(users, fn u -> u.id in existing_participant_ids end)

    participants_to_add =
      available_users
      |> Enum.take_random(min(count, length(available_users)))

    Enum.each(participants_to_add, fn user ->
      Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        status: "confirmed",
        role: "participant"
      })
    end)

    # Return all participants for this event
    Repo.all(
      from ep in Events.EventParticipant,
      where: ep.event_id == ^event.id,
      preload: [:user]
    )
  end

  # ============================================================================
  # Phase VI: Rich Data Helpers (API Integration)
  # ============================================================================

  defp fetch_movie_option(query) do
    IO.puts("    🎬 Fetching movie: #{query}")
    case RichDataManager.search(query, %{providers: [:tmdb], content_type: :movie, limit: 1}) do
      {:ok, %{tmdb: {:ok, [result | _]}}} ->
        IO.puts("      ✅ Got image: #{result.image_url}")
        %{
          title: result.title,
          description: result.description || "Classic film",
          image_url: result.image_url,
          metadata: result.metadata
        }

      _ ->
        # Fallback to simple data if API fails
        IO.puts("      ⚠ TMDB API unavailable for '#{query}', using fallback")
        %{title: query, description: "Classic film"}
    end
  end

  defp fetch_cocktail_option(query) do
    case RichDataManager.search(query, %{providers: [:cocktaildb], limit: 1}) do
      {:ok, %{cocktaildb: {:ok, [result | _]}}} ->
        %{
          title: result.title,
          description: result.description,
          image_url: result.image_url,
          metadata: result.metadata
        }

      _ ->
        # Fallback to simple data if API fails
        IO.puts("    ⚠ CocktailDB API unavailable for '#{query}', using fallback")
        %{title: query, description: "Classic cocktail"}
    end
  end

  defp fetch_music_option(query) do
    case RichDataManager.search(query, %{providers: [:spotify], limit: 1}) do
      {:ok, %{spotify: {:ok, [result | _]}}} ->
        %{
          title: result.title,
          description: result.description,
          image_url: result.image_url,
          metadata: result.metadata
        }

      _ ->
        # Fallback to simple data if API fails
        IO.puts("    ⚠ Spotify API unavailable for '#{query}', using fallback")
        %{title: query, description: "Popular track"}
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp add_sample_votes(poll, participants, vote_count) do
    # Get poll options
    options = Repo.all(from o in Events.PollOption, where: o.poll_id == ^poll.id)

    if length(options) == 0 do
      IO.puts("    ⚠ No options found for poll #{poll.id}")
      nil
    else

    # Add sample votes based on voting system
    voters = Enum.take_random(participants, min(vote_count, length(participants)))

    Enum.each(voters, fn participant ->
      case poll.voting_system do
        "binary" ->
          # Vote on random subset of options
          Enum.take_random(options, :rand.uniform(length(options)))
          |> Enum.each(fn option ->
            Events.create_poll_vote(
              option,
              participant.user,
              %{vote_value: Enum.random(["yes", "no", "maybe"])},
              "binary"
            )
          end)

        "approval" ->
          # Select random number of options (up to max_selections)
          max_selections = get_in(poll.settings, ["max_selections"]) || 2
          Enum.take_random(options, min(max_selections, length(options)))
          |> Enum.each(fn option ->
            Events.create_poll_vote(
              option,
              participant.user,
              %{vote_value: "approved"},
              "approval"
            )
          end)

        "ranked" ->
          # Rank random subset of options
          Enum.shuffle(options)
          |> Enum.take(:rand.uniform(length(options)))
          |> Enum.with_index(1)
          |> Enum.each(fn {option, rank} ->
            Events.create_poll_vote(
              option,
              participant.user,
              %{vote_value: "ranked", rank: rank},
              "ranked"
            )
          end)

        "star" ->
          # Rate each option with 1-5 stars
          Enum.each(options, fn option ->
            Events.create_poll_vote(
              option,
              participant.user,
              %{vote_value: "star", star_rating: :rand.uniform(5)},
              "star"
            )
          end)
      end
    end)
    end
  end
end

# Auto-run when file is executed directly
if __ENV__.file == :code.get_path() do
  MobileTestingPolls.run()
end
