defmodule EventasaurusWeb.ProfileController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User

  @doc """
  Shows a user's public profile page.

  Both /user/:username and /u/:username redirect here.
  Returns 404 if user doesn't exist or profile is private.
  """
  def show(conn, %{"username" => username}) do
    case Accounts.get_user_by_username(username) do
      nil ->
        # User doesn't exist
        conn
        |> put_status(:not_found)
        |> put_view(EventasaurusWeb.ErrorHTML)
        |> render("404.html", page_title: "User not found")

      user ->
        case user.profile_public do
          true ->
            # Public profile - show the profile page
            conn
            |> assign(:user, user)
            |> assign(:page_title, "#{User.display_name(user)} (@#{user.username})")
            |> render(:show)

          false ->
            # Private profile - check if it's the current user viewing their own profile
            auth_user = conn.assigns[:auth_user]

            if auth_user && auth_user.id == user.id do
              # User viewing their own private profile
              conn
              |> assign(:user, user)
              |> assign(:page_title, "Your Profile (@#{user.username})")
              |> assign(:is_own_profile, true)
              |> render(:show)
            else
              # Profile is private and not viewing own profile
              conn
              |> put_status(:not_found)
              |> put_view(EventasaurusWeb.ErrorHTML)
              |> render("404.html", page_title: "User not found")
            end

          nil ->
            # Profile publicity not set (treat as private)
            auth_user = conn.assigns[:auth_user]

            if auth_user && auth_user.id == user.id do
              conn
              |> assign(:user, user)
              |> assign(:page_title, "Your Profile (@#{user.username})")
              |> assign(:is_own_profile, true)
              |> render(:show)
            else
              conn
              |> put_status(:not_found)
              |> put_view(EventasaurusWeb.ErrorHTML)
              |> render("404.html", page_title: "User not found")
            end
        end
    end
  end

  @doc """
  Redirect short URL /u/:username to full URL /user/:username

  This provides a shorter, more shareable URL format.
  """
  def redirect_short(conn, %{"username" => username}) do
    # Validate username exists and profile is accessible before redirecting
    case Accounts.get_user_by_username(username) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(EventasaurusWeb.ErrorHTML)
        |> render("404.html", page_title: "User not found")

      user ->
        # Check if profile is accessible
        auth_user = conn.assigns[:auth_user]

        case user.profile_public do
          true ->
            # Public profile - redirect
            redirect(conn, to: ~p"/user/#{username}")

          _ ->
            # Private profile - only redirect if viewing own profile
            if auth_user && auth_user.id == user.id do
              redirect(conn, to: ~p"/user/#{username}")
            else
              conn
              |> put_status(:not_found)
              |> put_view(EventasaurusWeb.ErrorHTML)
              |> render("404.html", page_title: "User not found")
            end
        end
    end
  end
end
