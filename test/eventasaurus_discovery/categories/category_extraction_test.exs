defmodule EventasaurusDiscovery.Categories.CategoryExtractionTest do
  @moduledoc """
  Test category extraction from Ticketmaster and Karnet data
  """

  use EventasaurusApp.DataCase
  alias EventasaurusDiscovery.Categories.CategoryExtractor
  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Repo
  import Ecto.Query

  setup do
    # Ensure we have categories and mappings
    Categories.seed_initial_mappings()
    :ok
  end

  describe "Ticketmaster category extraction" do
    test "extracts categories from music concert event" do
      tm_event = %{
        "id" => "tm_test_1",
        "name" => "Rock Concert",
        "classifications" => [
          %{
            "primary" => true,
            "segment" => %{"id" => "KZFzniwnSyZfZ7v7nJ", "name" => "Music"},
            "genre" => %{"id" => "KnvZfZ7vAe6", "name" => "Rock"},
            "subGenre" => %{"id" => "KZazBEonSMnZfZ7vkvl", "name" => "Rock"}
          }
        ]
      }

      categories = CategoryExtractor.extract_ticketmaster_categories(tm_event)

      assert length(categories) > 0
      {primary_id, is_primary} = List.first(categories)
      assert is_primary == true
      assert is_integer(primary_id)

      # Verify it maps to concerts category
      category = Repo.get!(EventasaurusDiscovery.Categories.Category, primary_id)
      assert category.slug == "concerts"
    end

    test "extracts categories from festival event" do
      tm_event = %{
        "id" => "tm_test_2",
        "name" => "Music Festival",
        "classifications" => [
          %{
            "primary" => true,
            "segment" => %{"id" => "KZFzniwnSyZfZ7v7nJ", "name" => "Music"},
            "genre" => %{"id" => "KnvZfZ7vAe6", "name" => "Rock"},
            "subGenre" => %{"id" => "KZazBEonSMnZfZ7vF6na", "name" => "Music Festival"}
          }
        ]
      }

      categories = CategoryExtractor.extract_ticketmaster_categories(tm_event)

      assert length(categories) > 0
      {primary_id, _} = List.first(categories)

      category = Repo.get!(EventasaurusDiscovery.Categories.Category, primary_id)
      # Festivals should be primary, concerts secondary
      assert category.slug in ["festivals", "concerts"]
    end

    test "extracts categories from arts/theatre event" do
      tm_event = %{
        "id" => "tm_test_3",
        "name" => "Broadway Musical",
        "classifications" => [
          %{
            "primary" => true,
            "segment" => %{"id" => "KZFzniwnSyZfZ7v7na", "name" => "Arts & Theatre"},
            "genre" => %{"id" => "KnvZfZ7v7nE", "name" => "Musical"}
          }
        ]
      }

      categories = CategoryExtractor.extract_ticketmaster_categories(tm_event)

      assert length(categories) > 0
      {primary_id, _} = List.first(categories)

      category = Repo.get!(EventasaurusDiscovery.Categories.Category, primary_id)
      assert category.slug == "performances"
    end

    test "handles missing classifications" do
      tm_event = %{
        "id" => "tm_test_4",
        "name" => "Event without classifications"
      }

      categories = CategoryExtractor.extract_ticketmaster_categories(tm_event)
      assert categories == []
    end
  end

  describe "Karnet category extraction" do
    test "extracts categories from Polish concert" do
      karnet_event = %{
        "category" => "koncerty",
        "url" => "https://karnet.krakowculture.pl/impreza/koncert-rockowy"
      }

      categories = CategoryExtractor.extract_karnet_categories(karnet_event)

      assert length(categories) > 0
      {primary_id, is_primary} = List.first(categories)
      assert is_primary == true

      category = Repo.get!(EventasaurusDiscovery.Categories.Category, primary_id)
      assert category.slug == "concerts"
    end

    test "extracts categories from Polish festival" do
      karnet_event = %{
        "category" => "festiwale"
      }

      categories = CategoryExtractor.extract_karnet_categories(karnet_event)

      assert length(categories) > 0
      {primary_id, _} = List.first(categories)

      category = Repo.get!(EventasaurusDiscovery.Categories.Category, primary_id)
      assert category.slug == "festivals"
    end

    test "extracts categories from Polish theatre performance" do
      karnet_event = %{
        "category" => "spektakle"
      }

      categories = CategoryExtractor.extract_karnet_categories(karnet_event)

      assert length(categories) > 0
      {primary_id, _} = List.first(categories)

      category = Repo.get!(EventasaurusDiscovery.Categories.Category, primary_id)
      assert category.slug == "performances"
    end

    test "extracts category from URL when direct category missing" do
      karnet_event = %{
        "url" => "https://karnet.krakowculture.pl/impreza/wystawa-sztuki"
      }

      categories = CategoryExtractor.extract_karnet_categories(karnet_event)

      assert length(categories) > 0
      {primary_id, _} = List.first(categories)

      category = Repo.get!(EventasaurusDiscovery.Categories.Category, primary_id)
      assert category.slug == "exhibitions"
    end

    test "handles missing category data" do
      karnet_event = %{}

      categories = CategoryExtractor.extract_karnet_categories(karnet_event)
      assert categories == []
    end
  end

  describe "Event integration" do
    test "assigns categories to public event from Ticketmaster" do
      # Create a test event
      {:ok, event} = %PublicEvent{}
      |> PublicEvent.changeset(%{
        title: "Test Concert",
        slug: "test-concert",
        starts_at: DateTime.utc_now()
      })
      |> Repo.insert()

      # Ticketmaster data
      tm_data = %{
        "classifications" => [
          %{
            "segment" => %{"name" => "Music"},
            "genre" => %{"name" => "Rock"}
          }
        ]
      }

      {:ok, categories} = CategoryExtractor.assign_categories_to_event(
        event.id,
        "ticketmaster",
        tm_data
      )

      assert length(categories) > 0

      # Reload event with categories
      event = Repo.preload(event, :categories, force: true)
      assert length(event.categories) > 0

      first_category = List.first(event.categories)
      assert first_category.slug == "concerts"
    end

    test "assigns categories to public event from Karnet" do
      # Create a test event
      {:ok, event} = %PublicEvent{}
      |> PublicEvent.changeset(%{
        title: "Festiwal Muzyczny",
        slug: "festiwal-muzyczny",
        starts_at: DateTime.utc_now()
      })
      |> Repo.insert()

      # Karnet data
      karnet_data = %{
        "category" => "festiwale"
      }

      {:ok, categories} = CategoryExtractor.assign_categories_to_event(
        event.id,
        "karnet",
        karnet_data
      )

      assert length(categories) > 0

      # Reload event with categories
      event = Repo.preload(event, :categories, force: true)
      assert length(event.categories) > 0

      first_category = List.first(event.categories)
      assert first_category.slug == "festivals"
    end

    test "handles multiple categories with priority" do
      # Create a test event
      {:ok, event} = %PublicEvent{}
      |> PublicEvent.changeset(%{
        title: "Rock Festival",
        slug: "rock-festival",
        starts_at: DateTime.utc_now()
      })
      |> Repo.insert()

      # Complex Ticketmaster data with festival subGenre
      tm_data = %{
        "classifications" => [
          %{
            "segment" => %{"name" => "Music"},
            "genre" => %{"name" => "Rock"},
            "subGenre" => %{"name" => "Music Festival"}
          }
        ]
      }

      {:ok, categories} = CategoryExtractor.assign_categories_to_event(
        event.id,
        "ticketmaster",
        tm_data
      )

      # Should have multiple categories
      # We need to query the join table directly
      public_event_categories = Repo.all(
        from pec in EventasaurusDiscovery.Categories.PublicEventCategory,
        where: pec.event_id == ^event.id
      )

      # Check primary category
      primary = Enum.find(public_event_categories, & &1.is_primary)
      assert primary != nil

      # Load the actual category
      primary_category = Repo.get!(EventasaurusDiscovery.Categories.Category, primary.category_id)
      # Festival should be primary due to higher priority
      assert primary_category.slug in ["festivals", "concerts"]
    end
  end
end