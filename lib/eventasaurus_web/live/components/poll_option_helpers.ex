defmodule EventasaurusWeb.PollOptionHelpers do
  @moduledoc """
  Shared helpers for poll option display and metadata handling.

  These helpers are used across multiple poll components (movie, cocktail, generic)
  to extract and format import attribution information from poll option metadata.
  """

  @doc """
  Extracts import information from a poll option's metadata.

  Returns the import_info map if present, otherwise nil.

  ## Examples

      iex> option = %{metadata: %{"import_info" => %{"source_event_title" => "Test Event"}}}
      iex> get_import_info(option)
      %{"source_event_title" => "Test Event"}

      iex> option = %{metadata: %{}}
      iex> get_import_info(option)
      nil
  """
  def get_import_info(option) do
    with %{metadata: metadata} when is_map(metadata) <- option,
         import_info when is_map(import_info) <-
           metadata["import_info"] || metadata[:import_info] do
      import_info
    else
      _ -> nil
    end
  end

  @doc """
  Formats import attribution information for display.

  Generates a human-readable string describing where the poll option was imported from
  and who originally suggested it.

  ## Examples

      iex> import_info = %{"source_event_title" => "Movie Night", "original_recommender_name" => "Alice"}
      iex> format_import_attribution(import_info)
      "Imported from \\"Movie Night\\" (originally by Alice)"

      iex> import_info = %{"source_event_title" => "Movie Night"}
      iex> format_import_attribution(import_info)
      "Imported from \\"Movie Night\\""

      iex> format_import_attribution(nil)
      nil
  """
  def format_import_attribution(import_info) when is_map(import_info) do
    event_title = import_info["source_event_title"] || import_info[:source_event_title]

    recommender_name =
      import_info["original_recommender_name"] || import_info[:original_recommender_name]

    cond do
      event_title && recommender_name ->
        "Imported from \"#{event_title}\" (originally by #{recommender_name})"

      event_title ->
        "Imported from \"#{event_title}\""

      recommender_name ->
        "Originally suggested by #{recommender_name}"

      true ->
        "Imported from previous event"
    end
  end

  def format_import_attribution(_), do: nil
end
