# Source seeds for EventasaurusDiscovery

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Sources.Source

sources = [
  %{
    name: "Bandsintown",
    slug: "bandsintown",
    website_url: "https://www.bandsintown.com",
    priority: 80,
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
    metadata: %{
      "rate_limit_seconds" => 0.5,
      "max_requests_per_hour" => 7200,
      "api_type" => "graphql",
      "supports_pagination" => true
    }
  },
  %{
    name: "Ticketmaster",
    slug: "ticketmaster",
    website_url: "https://www.ticketmaster.com",
    priority: 70,
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 1000
    }
  },
  %{
    name: "StubHub",
    slug: "stubhub",
    website_url: "https://www.stubhub.com",
    priority: 60,
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 800
    }
  },
  %{
    name: "PubQuiz Poland",
    slug: "pubquiz-pl",
    website_url: "https://pubquiz.pl",
    priority: 25,
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 300,
      "language" => "pl",
      "supports_recurring_events" => true
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