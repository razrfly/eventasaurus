# Source seeds for EventasaurusDiscovery

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Sources.Source

sources = [
  %{
    name: "Bandsintown",
    slug: "bandsintown",
    website_url: "https://www.bandsintown.com",
    priority: 80,
    config: %{
      "rate_limit_seconds" => 3,
      "max_requests_per_hour" => 500,
      "user_agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
  },
  %{
    name: "Ticketmaster",
    slug: "ticketmaster",
    website_url: "https://www.ticketmaster.com",
    priority: 70,
    config: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 1000
    }
  },
  %{
    name: "StubHub",
    slug: "stubhub",
    website_url: "https://www.stubhub.com",
    priority: 60,
    config: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 800
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