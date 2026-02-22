defmodule EventasaurusWeb.Resolvers.Helpers do
  @moduledoc """
  Shared helper functions for GraphQL resolvers.
  """

  @doc """
  Formats Ecto changeset errors into a list of `%{field: String.t(), message: String.t()}` maps
  suitable for GraphQL error responses.
  """
  @spec format_changeset_errors(Ecto.Changeset.t()) :: [%{field: String.t(), message: String.t()}]
  def format_changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        atom_key =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> nil
          end

        value = if atom_key, do: Keyword.get(opts, atom_key), else: nil
        to_string(value || key)
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message ->
        %{field: to_string(field), message: message}
      end)
    end)
  end
end
