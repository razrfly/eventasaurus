defmodule EventasaurusWeb.Schema.Middleware.ChangesetErrors do
  @moduledoc """
  Absinthe middleware that intercepts Ecto changeset errors and formats
  them into the `InputError` type ({field, message} pairs).

  Applied as an after-middleware on mutations via the schema's `middleware/3` callback.
  """

  @behaviour Absinthe.Middleware

  @impl true
  def call(resolution, _config) do
    %{resolution | errors: Enum.flat_map(resolution.errors, &handle_error/1)}
  end

  defp handle_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message ->
        %{message: message, field: to_string(field)}
      end)
    end)
  end

  defp handle_error(error), do: [error]
end
