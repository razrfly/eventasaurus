defmodule EventasaurusWeb.Schema.Middleware.Authenticate do
  @moduledoc """
  Absinthe middleware that ensures the current user is authenticated.
  Returns an UNAUTHENTICATED error if no user is in context.
  """

  @behaviour Absinthe.Middleware

  @impl true
  def call(resolution, _config) do
    case resolution.context do
      %{current_user: %EventasaurusApp.Accounts.User{}} ->
        resolution

      _ ->
        resolution
        |> Absinthe.Resolution.put_result(
          {:error, message: "UNAUTHENTICATED", code: "UNAUTHENTICATED"}
        )
    end
  end
end
