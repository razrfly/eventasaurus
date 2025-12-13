# Source seeds for EventasaurusDiscovery

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Sources.Source

sources = [
  %{
    name: "Ticketmaster",
    slug: "ticketmaster",
    website_url: "https://www.ticketmaster.com",
    priority: 100,
    domains: ["music", "sports", "theater", "general"],
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 1000
    }
  },
  %{
    name: "Bandsintown",
    slug: "bandsintown",
    website_url: "https://www.bandsintown.com",
    priority: 80,
    domains: ["music", "concert"],
    metadata: %{
      "rate_limit_seconds" => 3,
      "max_requests_per_hour" => 500,
      "user_agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
  },
  %{
    name: "Resident Advisor",
    slug: "resident-advisor",
    website_url: "https://ra.co",
    priority: 75,
    domains: ["music", "concert"],
    metadata: %{
      "rate_limit_seconds" => 0.5,
      "max_requests_per_hour" => 7200,
      "api_type" => "graphql",
      "supports_pagination" => true
    }
  },
  %{
    name: "Karnet Kraków",
    slug: "karnet",
    website_url: "https://karnet.krakowculture.pl",
    priority: 70,
    domains: ["music", "theater", "cultural", "general"],
    metadata: %{
      "rate_limit_seconds" => 4,
      "max_requests_per_hour" => 900,
      "language" => "pl",
      "encoding" => "UTF-8",
      "supports_pagination" => true,
      "supports_filters" => true,
      "event_types" => ["festivals", "concerts", "performances", "exhibitions", "outdoor"]
    }
  },
  %{
    name: "Question One",
    slug: "question-one",
    website_url: "https://www.questionone.co.uk",
    priority: 35,
    domains: ["trivia"],
    aggregate_on_index: true,
    aggregation_type: "SocialEvent",
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 300,
      "language" => "en",
      "supports_recurring_events" => true
    }
  },
  %{
    name: "Geeks Who Drink",
    slug: "geeks-who-drink",
    website_url: "https://www.geekswhodrink.com",
    priority: 35,
    domains: ["trivia"],
    aggregate_on_index: true,
    aggregation_type: "SocialEvent",
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 300,
      "language" => "en",
      "supports_recurring_events" => true
    }
  },
  %{
    name: "Quizmeisters",
    slug: "quizmeisters",
    website_url: "https://quizmeisters.com",
    priority: 35,
    domains: ["trivia"],
    aggregate_on_index: true,
    aggregation_type: "SocialEvent",
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 300,
      "language" => "en",
      "supports_recurring_events" => true,
      "api_endpoint" => "https://storerocket.io/api/user/kDJ3BbK4mn/locations"
    }
  },
  %{
    name: "PubQuiz Poland",
    slug: "pubquiz-pl",
    website_url: "https://pubquiz.pl",
    priority: 25,
    domains: ["trivia"],
    aggregate_on_index: true,
    aggregation_type: "SocialEvent",
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 300,
      "language" => "pl",
      "supports_recurring_events" => true
    }
  },
  %{
    name: "Inquizition",
    slug: "inquizition",
    website_url: "https://inquizition.com",
    priority: 35,
    domains: ["trivia"],
    aggregate_on_index: true,
    aggregation_type: "SocialEvent",
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 300,
      "language" => "en",
      "supports_recurring_events" => true
    }
  },
  %{
    name: "Speed Quizzing",
    slug: "speed-quizzing",
    website_url: "https://speedquizzing.com",
    priority: 35,
    domains: ["trivia"],
    aggregate_on_index: true,
    aggregation_type: "SocialEvent",
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 300,
      "language" => "en",
      "supports_recurring_events" => true,
      "supports_performer_details" => true,
      "has_coordinates" => true,
      "coverage" => "UK, US, UAE, international",
      "scope" => "regional"
    }
  },
  %{
    name: "Sortiraparis",
    slug: "sortiraparis",
    website_url: "https://www.sortiraparis.com",
    priority: 65,
    domains: ["music", "cultural", "theater", "general"],
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 500,
      "language" => "fr",
      "supports_multilingual" => true,
      "coverage" => "Paris, France",
      "requires_geocoding" => true,
      "scope" => "city"
    }
  },
  %{
    name: "Cinema City",
    slug: "cinema-city",
    website_url: "https://www.cinema-city.pl",
    priority: 15,
    domains: ["screening", "cinema", "movies"],
    aggregate_on_index: true,
    aggregation_type: "ScreeningEvent",
    metadata: %{
      "rate_limit_seconds" => 1,
      "max_requests_per_hour" => 500,
      "language" => "pl",
      "supports_screenings" => true
    }
  },
  %{
    name: "Repertuary",
    slug: "repertuary",
    website_url: "https://repertuary.pl",
    priority: 15,
    domains: ["screening", "cinema", "movies"],
    aggregate_on_index: true,
    aggregation_type: "ScreeningEvent",
    metadata: %{
      "rate_limit_seconds" => 1,
      "max_requests_per_hour" => 500,
      "language" => "pl",
      "supports_screenings" => true,
      "supports_multi_city" => true
    }
  },
  %{
    name: "Waw4Free",
    slug: "waw4free",
    website_url: "https://waw4free.pl",
    priority: 35,
    domains: ["cultural", "general"],
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 300,
      "language" => "pl",
      "supports_pagination" => false,
      "all_events_free" => true,
      "coverage" => "Warsaw, Poland",
      "scope" => "city"
    }
  },
  %{
    name: "Restaurant Week",
    slug: "week_pl",
    website_url: "https://week.pl",
    priority: 45,
    domains: ["food", "festival"],
    aggregate_on_index: true,
    aggregation_type: "FoodEvent",
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 1800,
      "language" => "pl",
      "supports_pagination" => true,
      "requires_geocoding" => false,
      "has_coordinates" => true,
      "coverage" => "13 Polish cities",
      "scope" => "regional",
      "event_types" => ["restaurant_week", "fine_dining_week", "breakfast_week"],
      "consolidation_type" => "daily",
      "occurrence_type" => "explicit",
      "api_type" => "graphql",
      "requires_build_id" => false
    }
  },
  %{
    name: "Kupbilecik",
    slug: "kupbilecik",
    website_url: "https://www.kupbilecik.pl",
    priority: 60,
    domains: ["music", "theater", "cultural", "general"],
    metadata: %{
      "rate_limit_seconds" => 3,
      "max_requests_per_hour" => 1200,
      "language" => "pl",
      "supports_pagination" => false,
      "requires_geocoding" => true,
      "coverage" => "Poland",
      "scope" => "national",
      "access_pattern" => "sitemap_zyte",
      "requires_js_rendering" => true,
      "sitemap_count" => 5,
      "estimated_events" => 4100
    }
  }
]

Enum.each(sources, fn source_attrs ->
  case Repo.get_by(Source, slug: source_attrs.slug) do
    nil ->
      %Source{}
      |> Source.changeset(source_attrs)
      |> Repo.insert!()
      IO.puts("Created source: #{source_attrs.name}")

    existing ->
      existing
      |> Source.changeset(source_attrs)
      |> Repo.update!()
      IO.puts("Updated source: #{source_attrs.name}")
  end
end)

IO.puts("\n✅ Sources seeded successfully!")