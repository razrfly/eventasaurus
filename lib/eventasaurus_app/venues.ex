defmodule EventasaurusApp.Venues do
  @moduledoc """
  The Venues context.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue

  @doc """
  Returns the list of venues.

  ## Options
  - `:type` - Filter venues by venue_type (e.g., "venue", "city", "region", "online", "tbd")
  - `:name` - Filter venues by name (case-insensitive partial match)

  ## Examples

      list_venues()
      list_venues(type: "venue")
      list_venues(type: "online", name: "zoom")
  """
  def list_venues(opts \\ []) do
    type = Keyword.get(opts, :type)
    name = Keyword.get(opts, :name)

    Venue
    |> venue_type_filter(type)
    |> venue_name_filter(name)
    |> Repo.all()
  end

  @doc """
  Gets a single venue.

  Raises `Ecto.NoResultsError` if the Venue does not exist.
  """
  def get_venue!(id), do: Repo.get!(Venue, id)

  @doc """
  Gets a single venue.

  Returns nil if the Venue does not exist.
  """
  def get_venue(id), do: Repo.get(Venue, id)

  @doc """
  Creates a venue.
  """
  def create_venue(attrs \\ %{}) do
    %Venue{}
    |> Venue.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a venue.
  """
  def update_venue(%Venue{} = venue, attrs) do
    venue
    |> Venue.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a venue.
  """
  def delete_venue(%Venue{} = venue) do
    Repo.delete(venue)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking venue changes.
  """
  def change_venue(%Venue{} = venue, attrs \\ %{}) do
    Venue.changeset(venue, attrs)
  end

  @doc """
  Returns the list of venues with name search.
  """
  def search_venues(name) do
    from(v in Venue, where: ilike(v.name, ^"%#{name}%"))
    |> Repo.all()
  end

  @doc """
  Lists venues filtered by venue type.
  """
  def list_venues_by_type(venue_type) when is_binary(venue_type) do
    list_venues(type: venue_type)
  end

  # Private helper functions for query filtering

  defp venue_type_filter(query, nil), do: query
  defp venue_type_filter(query, type) when is_binary(type) do
    from(v in query, where: v.venue_type == ^type)
  end

  defp venue_name_filter(query, nil), do: query
  defp venue_name_filter(query, name) when is_binary(name) do
    from(v in query, where: ilike(v.name, ^"%#{name}%"))
  end

  @doc """
  Finds a venue by address.
  Returns nil if no venue with the given address exists.
  """
  def find_venue_by_address(address) when is_binary(address) do
    Repo.get_by(Venue, address: address)
  end
  def find_venue_by_address(_), do: nil
end
