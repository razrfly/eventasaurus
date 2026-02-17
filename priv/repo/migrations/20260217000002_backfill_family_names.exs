defmodule EventasaurusApp.Repo.Migrations.BackfillFamilyNames do
  @moduledoc """
  Backfill family_name for all users with NULL family_name.

  Assigns a random family name from the hardcoded list. This migration
  intentionally inlines the family name list rather than depending on
  application modules, following Ecto best practices for self-contained
  migrations.
  """
  use Ecto.Migration

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

  def up do
    result =
      Ecto.Adapters.SQL.query!(
        repo(),
        "SELECT id FROM users WHERE family_name IS NULL ORDER BY id",
        []
      )

    IO.puts("Found #{result.num_rows} users with NULL family_name")

    Enum.each(result.rows, fn [user_id] ->
      family_name = Enum.random(@family_names)
      IO.puts("Setting family_name for user #{user_id}: #{family_name}")

      Ecto.Adapters.SQL.query!(
        repo(),
        "UPDATE users SET family_name = $1 WHERE id = $2",
        [family_name, user_id]
      )
    end)

    IO.puts("Backfill complete!")
  end

  def down do
    Ecto.Adapters.SQL.query!(repo(), "UPDATE users SET family_name = NULL", [])
  end
end
