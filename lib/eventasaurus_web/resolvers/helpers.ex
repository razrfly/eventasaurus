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
        # Use to_existing_atom to avoid atom table pollution; returns nil on unknown atoms
        atom_key =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> nil
          end

        value = if atom_key, do: Keyword.get(opts, atom_key), else: nil
        to_string(if is_nil(value), do: key, else: value)
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      flatten_messages(to_string(field), messages)
    end)
  end

  # Recursively flatten error messages, handling nested maps from embeds_one/embeds_many
  defp flatten_messages(field, messages) when is_list(messages) do
    Enum.flat_map(messages, fn
      message when is_binary(message) ->
        [%{field: field, message: message}]

      nested when is_map(nested) ->
        Enum.flat_map(nested, fn {sub_field, sub_messages} ->
          flatten_messages("#{field}.#{sub_field}", sub_messages)
        end)
    end)
  end
end
