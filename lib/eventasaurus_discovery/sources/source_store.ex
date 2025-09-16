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
    slug =
      config
      |> get_val(:slug)
      |> normalize_blank()

    case slug do
      nil ->
        {:error, :invalid_config_slug}
      slug ->
        case Repo.get_by(Source, slug: slug) do
          nil -> create_source(config, slug)
          source -> {:ok, source}
        end
    end
  end

  defp create_source(config, slug) do
    # Build metadata without nils
    metadata =
      %{
        rate_limit: get_val(config, :rate_limit),
        timeout: get_val(config, :timeout),
        max_retries: get_val(config, :max_retries)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    %Source{}
    |> Source.changeset(%{
      name: get_val(config, :name),
      slug: slug,
      website_url:
        get_val(config, :website_url) ||
        get_val(config, :base_url),
      priority: get_val(config, :priority),
      is_active: true,
      metadata: metadata
    })
    |> Repo.insert()
    |> case do
      {:ok, source} ->
        {:ok, source}
      {:error, %Ecto.Changeset{} = changeset} ->
        # If another process inserted the same slug concurrently, fetch and return it
        if has_unique_constraint_error?(changeset, :slug) do
          case Repo.get_by(Source, slug: slug) do
            nil -> {:error, changeset}
            source -> {:ok, source}
          end
        else
          {:error, changeset}
        end
    end
  end

  # Helper to get value from map with both atom and string keys
  defp get_val(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  # Normalize blank values to nil
  defp normalize_blank(nil), do: nil
  defp normalize_blank(v) when is_binary(v) do
    v = String.trim(v)
    if v == "", do: nil, else: v
  end
  defp normalize_blank(v) when is_atom(v), do: v |> Atom.to_string() |> normalize_blank()
  defp normalize_blank(v), do: v |> to_string() |> normalize_blank()

  # Check if changeset has unique constraint error for a field
  defp has_unique_constraint_error?(changeset, field) do
    Enum.any?(changeset.errors, fn
      {^field, {_msg, opts}} ->
        Keyword.get(opts, :constraint) == :unique
      _ ->
        false
    end)
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