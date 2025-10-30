defmodule Eventasaurus.SitemapStats do
  @moduledoc """
  Provides statistics and validation for sitemap composition.
  Runs the same DB queries as sitemap generation but only counts URLs.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  import Ecto.Query

  @doc """
  Returns expected URL counts for each sitemap category.
  This shows what WOULD be in the sitemap if generated now.
  """
  def expected_counts do
    counts = %{
      static: count_static_urls(),
      activities: count_activities(),
      cities: count_city_urls(),
      venues: count_venues(),
      containers: count_containers()
    }

    Map.put(counts, :total, calculate_total(counts))
  end

  @doc """
  Returns sample URLs for each category to show in the dashboard.
  """
  def sample_urls(base_url \\ "https://wombie.com") do
    %{
      static: "#{base_url}/",
      activities: get_sample_activity_url(base_url),
      cities: "#{base_url}/c/krakow",
      venues: get_sample_venue_url(base_url),
      containers: get_sample_container_url(base_url)
    }
  end

  # Count static pages (fixed count)
  defp count_static_urls, do: 7

  # Count activities (public events with valid slugs)
  defp count_activities do
    from(pe in PublicEvent,
      select: count(pe.id),
      where:
        not is_nil(pe.slug) and
          not is_nil(pe.updated_at) and
          pe.slug != "" and
          fragment("? !~ ?", pe.slug, "^-")
    )
    |> Repo.one()
  end

  # Count city URLs (active cities × 10 subpages per city)
  defp count_city_urls do
    active_cities =
      from(c in EventasaurusDiscovery.Locations.City,
        select: count(c.id),
        where: c.discovery_enabled == true
      )
      |> Repo.one()

    # Each city has 10 pages: main + events + venues + search + 6 container types
    active_cities * 10
  end

  # Count venues in active cities
  defp count_venues do
    from(v in EventasaurusApp.Venues.Venue,
      join: c in EventasaurusDiscovery.Locations.City,
      on: v.city_id == c.id,
      select: count(v.id),
      where: c.discovery_enabled == true and not is_nil(v.slug)
    )
    |> Repo.one()
  end

  # Count containers in active cities
  defp count_containers do
    from(pec in EventasaurusDiscovery.PublicEvents.PublicEventContainer,
      join: pecm in EventasaurusDiscovery.PublicEvents.PublicEventContainerMembership,
      on: pecm.container_id == pec.id,
      join: pe in PublicEvent,
      on: pe.id == pecm.event_id,
      join: v in EventasaurusApp.Venues.Venue,
      on: v.id == pe.venue_id,
      join: c in EventasaurusDiscovery.Locations.City,
      on: c.id == v.city_id,
      select: count(pec.id, :distinct),
      where:
        not is_nil(pec.slug) and
          c.discovery_enabled == true
    )
    |> Repo.one()
  end

  # Get a sample activity URL
  defp get_sample_activity_url(base_url) do
    activity =
      from(pe in PublicEvent,
        select: pe.slug,
        where:
          not is_nil(pe.slug) and
            pe.slug != "" and
            fragment("? !~ ?", pe.slug, "^-"),
        limit: 1
      )
      |> Repo.one()

    if activity do
      "#{base_url}/activities/#{activity}"
    else
      nil
    end
  end

  # Get a sample venue URL
  defp get_sample_venue_url(base_url) do
    venue =
      from(v in EventasaurusApp.Venues.Venue,
        join: c in EventasaurusDiscovery.Locations.City,
        on: v.city_id == c.id,
        select: %{venue_slug: v.slug, city_slug: c.slug},
        where: c.discovery_enabled == true and not is_nil(v.slug),
        limit: 1
      )
      |> Repo.one()

    if venue do
      "#{base_url}/c/#{venue.city_slug}/venues/#{venue.venue_slug}"
    else
      nil
    end
  end

  # Get a sample container URL
  defp get_sample_container_url(base_url) do
    container =
      from(pec in EventasaurusDiscovery.PublicEvents.PublicEventContainer,
        join: pecm in EventasaurusDiscovery.PublicEvents.PublicEventContainerMembership,
        on: pecm.container_id == pec.id,
        join: pe in PublicEvent,
        on: pe.id == pecm.event_id,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == pe.venue_id,
        join: c in EventasaurusDiscovery.Locations.City,
        on: c.id == v.city_id,
        select: %{
          slug: pec.slug,
          container_type: pec.container_type,
          city_slug: c.slug
        },
        where:
          not is_nil(pec.slug) and
            c.discovery_enabled == true,
        limit: 1
      )
      |> Repo.one()

    if container do
      type_plural = pluralize_container_type(container.container_type)
      "#{base_url}/c/#{container.city_slug}/#{type_plural}/#{container.slug}"
    else
      nil
    end
  end

  # Convert container type to plural form
  defp pluralize_container_type(:festival), do: "festivals"
  defp pluralize_container_type(:conference), do: "conferences"
  defp pluralize_container_type(:tour), do: "tours"
  defp pluralize_container_type(:series), do: "series"
  defp pluralize_container_type(:exhibition), do: "exhibitions"
  defp pluralize_container_type(:tournament), do: "tournaments"
  defp pluralize_container_type(_), do: "unknown"

  # Calculate total from counts map
  defp calculate_total(counts) do
    counts.static + counts.activities + counts.cities + counts.venues + counts.containers
  end
end
