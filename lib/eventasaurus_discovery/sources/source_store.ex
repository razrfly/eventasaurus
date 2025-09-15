defmodule EventasaurusDiscovery.Sources.SourceStore do
  @moduledoc """
  Store for managing event sources in the database.

  Handles creating and retrieving source records consistently across all sources.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source

  @doc """
  Get or create a source based on configuration
  """
  def get_or_create_source(config) when is_map(config) do
    case Repo.get_by(Source, slug: config[:slug]) do
      nil -> create_source(config)
      source -> {:ok, source}
    end
  end

  defp create_source(config) do
    %Source{}
    |> Source.changeset(%{
      name: config[:name],
      slug: config[:slug],
      website_url: config[:website_url] || config[:base_url],
      priority: config[:priority],
      is_active: true,
      metadata: %{
        rate_limit: config[:rate_limit],
        timeout: config[:timeout],
        max_retries: config[:max_retries]
      }
    })
    |> Repo.insert()
  end

  @doc """
  Get source by slug
  """
  def get_source_by_slug(slug) do
    Repo.get_by(Source, slug: slug)
  end

  @doc """
  List all active sources
  """
  def list_active_sources do
    from(s in Source, where: s.is_active == true, order_by: [desc: s.priority])
    |> Repo.all()
  end
end