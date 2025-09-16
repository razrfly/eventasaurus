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
    slug = Map.get(config, :slug) || Map.get(config, "slug")

    case slug do
      nil ->
        {:error, :invalid_config_slug}
      _ ->
        case Repo.get_by(Source, slug: slug) do
          nil -> create_source(config)
          source -> {:ok, source}
        end
    end
  end

  defp create_source(config) do
    # Helper to get value from map with both atom and string keys
    get_val = fn map, atom_key, string_key ->
      Map.get(map, atom_key) || Map.get(map, string_key)
    end

    # Build metadata without nils
    metadata =
      %{
        rate_limit: get_val.(config, :rate_limit, "rate_limit"),
        timeout: get_val.(config, :timeout, "timeout"),
        max_retries: get_val.(config, :max_retries, "max_retries")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    %Source{}
    |> Source.changeset(%{
      name: get_val.(config, :name, "name"),
      slug: get_val.(config, :slug, "slug"),
      website_url:
        get_val.(config, :website_url, "website_url") ||
        get_val.(config, :base_url, "base_url"),
      priority: get_val.(config, :priority, "priority"),
      is_active: true,
      metadata: metadata
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