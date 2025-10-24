defmodule EventasaurusWeb.Helpers.LanguageDiscoveryTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusWeb.Helpers.LanguageDiscovery
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Venues.Venue

  describe "get_available_languages_for_city/1" do
    setup do
      # Create test country with known languages
      country =
        %Country{}
        |> Country.changeset(%{
          name: "France",
          code: "FR",
          slug: "france"
        })
        |> Repo.insert!()

      # Create test city
      city =
        %City{}
        |> City.changeset(%{
          name: "Paris",
          slug: "paris",
          country_id: country.id,
          latitude: 48.8566,
          longitude: 2.3522
        })
        |> Repo.insert!()

      # Create venue in Paris
      venue =
        %Venue{}
        |> Venue.changeset(%{
          name: "Test Venue",
          slug: "test-venue",
          city_id: city.id,
          latitude: 48.8566,
          longitude: 2.3522
        })
        |> Repo.insert!()

      # Create event with French translations
      event =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          title: "Test Event",
          slug: "test-event-#{System.unique_integer([:positive])}",
          venue_id: venue.id,
          starts_at: DateTime.utc_now(),
          title_translations: %{"fr" => "Événement Test", "en" => "Test Event"}
        })
        |> Repo.insert!()

      %{city: city, country: country, venue: venue, event: event}
    end

    test "returns languages spoken in country plus English", %{city: city} do
      languages = LanguageDiscovery.get_available_languages_for_city(city.slug)

      # Should include English (always)
      assert "en" in languages

      # Should include French (France's language from Countries library)
      assert "fr" in languages

      # Should be sorted
      assert languages == Enum.sort(languages)
    end

    test "returns only English for unknown city" do
      languages = LanguageDiscovery.get_available_languages_for_city("unknown-city-slug")
      assert languages == ["en"]
    end

    test "includes languages from database translations", %{city: city} do
      languages = LanguageDiscovery.get_available_languages_for_city(city.slug)

      # Should include French from both country data and DB translations
      assert "fr" in languages
      assert "en" in languages
    end
  end

  describe "get_available_languages_for_activity/1" do
    setup do
      country =
        %Country{}
        |> Country.changeset(%{
          name: "Spain",
          code: "ES",
          slug: "spain"
        })
        |> Repo.insert!()

      city =
        %City{}
        |> City.changeset(%{
          name: "Madrid",
          slug: "madrid",
          country_id: country.id,
          latitude: 40.4168,
          longitude: -3.7038
        })
        |> Repo.insert!()

      venue =
        %Venue{}
        |> Venue.changeset(%{
          name: "Madrid Venue",
          slug: "madrid-venue",
          city_id: city.id,
          latitude: 40.4168,
          longitude: -3.7038
        })
        |> Repo.insert!()

      %{city: city, country: country, venue: venue}
    end

    test "returns languages from activity title_translations", %{venue: venue} do
      event =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          title: "Spanish Event",
          slug: "spanish-event-#{System.unique_integer([:positive])}",
          venue_id: venue.id,
          starts_at: DateTime.utc_now(),
          title_translations: %{
            "es" => "Evento Español",
            "en" => "Spanish Event",
            "fr" => "Événement Espagnol"
          }
        })
        |> Repo.insert!()

      languages = LanguageDiscovery.get_available_languages_for_activity(event.id)

      assert "en" in languages
      assert "es" in languages
      assert "fr" in languages
      assert length(languages) == 3
    end

    test "returns only English when activity has no translations", %{venue: venue} do
      event =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          title: "No Translations",
          slug: "no-translations-#{System.unique_integer([:positive])}",
          venue_id: venue.id,
          starts_at: DateTime.utc_now(),
          title_translations: nil
        })
        |> Repo.insert!()

      languages = LanguageDiscovery.get_available_languages_for_activity(event.id)
      assert languages == ["en"]
    end

    test "returns only English for non-existent activity" do
      languages = LanguageDiscovery.get_available_languages_for_activity(999_999_999)
      assert languages == ["en"]
    end

    test "returns sorted language list", %{venue: venue} do
      event =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          title: "Multi-language Event",
          slug: "multi-lang-#{System.unique_integer([:positive])}",
          venue_id: venue.id,
          starts_at: DateTime.utc_now(),
          title_translations: %{"pl" => "Polski", "de" => "Deutsch", "en" => "English"}
        })
        |> Repo.insert!()

      languages = LanguageDiscovery.get_available_languages_for_activity(event.id)
      assert languages == Enum.sort(languages)
    end
  end

  describe "get_activity_language_context/2" do
    setup do
      country =
        %Country{}
        |> Country.changeset(%{
          name: "Poland",
          code: "PL",
          slug: "poland"
        })
        |> Repo.insert!()

      city =
        %City{}
        |> City.changeset(%{
          name: "Warsaw",
          slug: "warsaw",
          country_id: country.id,
          latitude: 52.2297,
          longitude: 21.0122
        })
        |> Repo.insert!()

      venue =
        %Venue{}
        |> Venue.changeset(%{
          name: "Warsaw Venue",
          slug: "warsaw-venue",
          city_id: city.id,
          latitude: 52.2297,
          longitude: 21.0122
        })
        |> Repo.insert!()

      %{city: city, venue: venue}
    end

    test "returns correct language context when activity has all city languages", %{
      city: city,
      venue: venue
    } do
      event =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          title: "Complete Translation",
          slug: "complete-#{System.unique_integer([:positive])}",
          venue_id: venue.id,
          starts_at: DateTime.utc_now(),
          title_translations: %{"pl" => "Polski", "en" => "English"}
        })
        |> Repo.insert!()

      context = LanguageDiscovery.get_activity_language_context(event.id, city.slug)

      assert "en" in context.available
      assert "pl" in context.available
      assert context.unavailable == []
      assert context.all == context.available
    end

    test "returns correct context when activity missing some city languages", %{
      city: city,
      venue: venue
    } do
      # Create another event in Warsaw with Polish translations so Polish appears in city languages
      %PublicEvent{}
      |> PublicEvent.changeset(%{
        title: "Polish Event",
        slug: "polish-event-#{System.unique_integer([:positive])}",
        venue_id: venue.id,
        starts_at: DateTime.utc_now(),
        title_translations: %{"pl" => "Polski Wydarzenie"}
      })
      |> Repo.insert!()

      # Create test event with only English
      event =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          title: "English Only",
          slug: "english-only-#{System.unique_integer([:positive])}",
          venue_id: venue.id,
          starts_at: DateTime.utc_now(),
          title_translations: %{"en" => "English Only"}
        })
        |> Repo.insert!()

      context = LanguageDiscovery.get_activity_language_context(event.id, city.slug)

      # Activity only has English
      assert "en" in context.available
      assert "pl" not in context.available

      # City has both Polish and English available
      assert "pl" in context.all or "pl" in context.unavailable
      assert "en" in context.all
    end

    test "all field combines available and unavailable languages", %{city: city, venue: venue} do
      event =
        %PublicEvent{}
        |> PublicEvent.changeset(%{
          title: "Test Event",
          slug: "test-#{System.unique_integer([:positive])}",
          venue_id: venue.id,
          starts_at: DateTime.utc_now(),
          title_translations: %{"en" => "English"}
        })
        |> Repo.insert!()

      context = LanguageDiscovery.get_activity_language_context(event.id, city.slug)

      # All should be the union of available and unavailable
      all_combined = Enum.sort(context.available ++ context.unavailable)
      assert Enum.sort(context.all) == all_combined
    end
  end

  describe "edge cases" do
    test "handles nil city slug gracefully" do
      # Should not crash, just return English
      languages = LanguageDiscovery.get_available_languages_for_city(nil)
      assert languages == ["en"]
    end

    test "handles empty string city slug" do
      languages = LanguageDiscovery.get_available_languages_for_city("")
      assert languages == ["en"]
    end

    test "deduplicates languages" do
      # If a language appears in both country data and DB translations,
      # it should only appear once in the result
      country =
        %Country{}
        |> Country.changeset(%{
          name: "Germany",
          code: "DE",
          slug: "germany"
        })
        |> Repo.insert!()

      city =
        %City{}
        |> City.changeset(%{
          name: "Berlin",
          slug: "berlin",
          country_id: country.id,
          latitude: 52.5200,
          longitude: 13.4050
        })
        |> Repo.insert!()

      venue =
        %Venue{}
        |> Venue.changeset(%{
          name: "Berlin Venue",
          slug: "berlin-venue",
          city_id: city.id,
          latitude: 52.5200,
          longitude: 13.4050
        })
        |> Repo.insert!()

      # Create event with German translations (German also from country)
      %PublicEvent{}
      |> PublicEvent.changeset(%{
        title: "German Event",
        slug: "german-event-#{System.unique_integer([:positive])}",
        venue_id: venue.id,
        starts_at: DateTime.utc_now(),
        title_translations: %{"de" => "Deutsches Ereignis", "en" => "German Event"}
      })
      |> Repo.insert!()

      languages = LanguageDiscovery.get_available_languages_for_city(city.slug)

      # German should only appear once
      assert length(languages) == length(Enum.uniq(languages))
      assert "de" in languages
      assert "en" in languages
    end
  end
end
