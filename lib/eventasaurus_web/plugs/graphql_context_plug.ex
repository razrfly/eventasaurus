defmodule EventasaurusWeb.Plugs.GraphQLContextPlug do
  @moduledoc """
  Copies the authenticated user from `conn.assigns` into the Absinthe context
  so that resolvers can access `context.current_user`.
  """

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    context = %{current_user: conn.assigns[:user]}
    Absinthe.Plug.put_options(conn, context: context)
  end
end
