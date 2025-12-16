defmodule Eventasaurus.SitemapStats do
  @moduledoc """
  Provides statistics and validation for sitemap composition.

  This module delegates to `Eventasaurus.Sitemap.url_stats/0` which is the
  single source of truth for sitemap categories. This ensures the admin
  dashboard always reflects the actual sitemap content.

  ## Architecture
  - `Sitemap.url_stats/0` defines all categories with counts and samples
  - `SitemapStats` transforms that data for backwards compatibility
  - Adding a new sitemap category only requires updating `Sitemap.url_stats/0`
  """

  alias Eventasaurus.Sitemap

  @doc """
  Returns expected URL counts for each sitemap category.
  This shows what WOULD be in the sitemap if generated now.

  Delegates to `Sitemap.url_stats/0` for the single source of truth.
  """
  @spec expected_counts() :: map()
  def expected_counts do
    stats = Sitemap.url_stats()

    counts =
      stats
      |> Enum.map(fn stat -> {stat.key, stat.count} end)
      |> Map.new()

    total = stats |> Enum.map(& &1.count) |> Enum.sum()
    Map.put(counts, :total, total)
  end

  @doc """
  Returns sample URLs for each category to show in the dashboard.

  Delegates to `Sitemap.url_stats/0` for the single source of truth.
  """
  @spec sample_urls(String.t()) :: map()
  def sample_urls(host \\ "wombie.com") do
    Sitemap.url_stats(host: host)
    |> Enum.map(fn stat -> {stat.key, stat.sample} end)
    |> Map.new()
  end

  @doc """
  Returns full category details for the admin dashboard.
  Includes: key, name, description, count, sample

  This is the preferred method for the admin UI as it provides
  richer information than expected_counts/0 and sample_urls/0.
  """
  @spec categories(String.t()) :: [map()]
  def categories(host \\ "wombie.com") do
    Sitemap.url_stats(host: host)
  end

  @doc """
  Returns the total URL count across all categories.
  """
  @spec total_count() :: non_neg_integer()
  def total_count do
    Sitemap.url_stats()
    |> Enum.map(& &1.count)
    |> Enum.sum()
  end
end
