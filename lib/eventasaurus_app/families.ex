defmodule EventasaurusApp.Families do
  @moduledoc """
  Artificial family assignment for users.

  Every user is permanently assigned a random family name from a hardcoded list
  of natural-world nouns. Inspired by Slapstick by Kurt Vonnegut.
  """

  @family_names ~w(
    Daffodil Oriole Raspberry Chipmunk Pachysandra
    Bauxite Uranium Oyster Chickadee Hollyhock
    Marigold Zinnia Petunia Foxglove Primrose Larkspur
    Persimmon Quince Mulberry Kumquat Gooseberry
    Wren Tanager Phoebe Junco Grackle
    Pangolin Axolotl Capybara Salamander
    Jasper Feldspar Obsidian Tourmaline Agate
    Cobalt Iridium Bismuth Tungsten
    Clover Fiddlehead Sagebrush Yarrow
    Nautilus Cuttlefish Sturgeon
  )

  @doc """
  Returns a random family name from the list.
  """
  @spec random_family_name() :: String.t()
  def random_family_name do
    Enum.random(@family_names)
  end

  @doc """
  Returns the full list of family names.
  """
  @spec list_family_names() :: [String.t()]
  def list_family_names do
    @family_names
  end

  @doc """
  Returns true if the given name is a valid family name.
  """
  @spec valid_family_name?(String.t()) :: boolean()
  def valid_family_name?(name) when is_binary(name) do
    name in @family_names
  end

  def valid_family_name?(_), do: false
end
