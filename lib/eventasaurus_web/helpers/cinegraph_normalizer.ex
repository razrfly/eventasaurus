defmodule EventasaurusWeb.Helpers.CinegraphNormalizer do
  @moduledoc """
  Shared normalization helpers for Cinegraph cast and crew data.

  Converts camelCase GraphQL JSON into the string-keyed map format expected by
  CastCarouselComponent and other movie components.
  """

  @doc """
  Normalizes a Cinegraph cast list to the CastCarouselComponent format.

  Returns an empty list for any non-list input (nil, missing data, etc.).
  """
  @spec normalize_cinegraph_cast(list(map()) | any()) :: list(map())
  def normalize_cinegraph_cast(cast) when is_list(cast) do
    Enum.map(cast, fn c ->
      %{
        "name" => get_in(c, ["person", "name"]),
        "character" => c["character"],
        "profile_path" => get_in(c, ["person", "profilePath"])
      }
    end)
  end

  def normalize_cinegraph_cast(_), do: []

  @doc """
  Normalizes a Cinegraph crew list to the component format.

  Returns an empty list for any non-list input (nil, missing data, etc.).
  """
  @spec normalize_cinegraph_crew(list(map()) | any()) :: list(map())
  def normalize_cinegraph_crew(crew) when is_list(crew) do
    Enum.map(crew, fn c ->
      %{
        "name" => get_in(c, ["person", "name"]),
        "job" => c["job"],
        "department" => c["department"],
        "profile_path" => get_in(c, ["person", "profilePath"])
      }
    end)
  end

  def normalize_cinegraph_crew(_), do: []
end
