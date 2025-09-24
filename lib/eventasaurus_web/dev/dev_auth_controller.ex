defmodule EventasaurusWeb.Dev.DevAuthController do
  @moduledoc """
  Development-only controller for quick user login.
  This controller is only available in development and test environments.
  """
  use EventasaurusWeb, :controller
  alias EventasaurusWeb.Dev.DevAuth
  require Logger

  @doc """
  Handle quick login request from development UI.
  """
  def quick_login(conn, %{"user_id" => user_id}) do
    if DevAuth.enabled?() do
      case DevAuth.quick_login(user_id) do
        {:ok, user} ->
          conn
          |> DevAuth.create_dev_session(user)
          |> put_flash(:info, "🚧 DEV: Logged in as #{user.name || user.email}")
          |> redirect(to: ~p"/dashboard")

        {:error, :user_not_found} ->
          conn
          |> put_flash(:error, "User not found")
          |> redirect(to: ~p"/auth/login")

        {:error, _} ->
          conn
          |> put_flash(:error, "Quick login failed")
          |> redirect(to: ~p"/auth/login")
      end
    else
      # In production, this route shouldn't even exist, but just in case
      conn
      |> send_resp(404, "Not found")
    end
  end
end
