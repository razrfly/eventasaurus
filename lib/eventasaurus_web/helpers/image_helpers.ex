defmodule EventasaurusWeb.Helpers.ImageHelpers do
  @moduledoc """
  Helper functions for image-related operations.
  """

  @doc """
  Generates a human-readable title from a filename by:
  - Removing common image extensions (case-insensitive)
  - Replacing underscores and hyphens with spaces
  - Capitalizing each word
  - Falling back to original filename if processing fails
  """
  @spec title_from_filename(String.t()) :: String.t()
  def title_from_filename(filename) do
    filename
    |> String.replace(~r/\.(png|jpe?g|gif|webp|svg)$/i, "")
    |> String.replace(~r/[_\-]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
    |> case do
      # fallback to original filename if processing fails
      "" -> filename
      title -> title
    end
  end
end
