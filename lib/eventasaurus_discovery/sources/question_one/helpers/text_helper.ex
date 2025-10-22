defmodule EventasaurusDiscovery.Sources.QuestionOne.Helpers.TextHelper do
  @moduledoc """
  Shared text processing utilities for Question One scraper.

  Ensures consistent external_id generation between IndexPageJob and Transformer.
  """

  @doc """
  Generate URL-safe slug from text by converting non-alphanumeric characters to underscores.

  Used to create stable external_ids for deduplication.

  ## Examples

      iex> slugify("Arab Boy, Putney")
      "arab_boy_putney"

      iex> slugify("The Crown & Anchor")
      "the_crown_anchor"
  """
  def slugify(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end
end
