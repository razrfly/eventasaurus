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
    case Accounts.get_user_by_username_or_id(username) do
      nil ->
        # User doesn't exist
        conn
        |> put_status(:not_found)
        |> put_view(EventasaurusWeb.ErrorHTML)
        |> render("404.html", page_title: "User not found")

      user ->
        canonical_username = User.username_slug(user)

        # Redirect to canonical URL if accessed via ID or different username format
        if username != canonical_username do
          redirect(conn, to: ~p"/user/#{canonical_username}")
        else
          if user.profile_public == true do
            # Public profile - show the profile page
            conn
            |> assign(:user, user)
            |> assign(:page_title, "#{User.display_name(user)} (@#{canonical_username})")
            |> render(:show)
          else
            # Private profile - check if it's the current user viewing their own profile
            auth_user = conn.assigns[:auth_user]

            if auth_user && auth_user.id == user.id do
              # User viewing their own private profile
              conn
              |> assign(:user, user)
              |> assign(:page_title, "Your Profile (@#{canonical_username})")
              |> assign(:is_own_profile, true)
              |> render(:show)
            else
              # Profile is private and not viewing own profile
              conn
              |> put_status(:not_found)
              |> put_view(EventasaurusWeb.ErrorHTML)
              |> render("404.html", page_title: "User not found")
            end
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
    case Accounts.get_user_by_username_or_id(username) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(EventasaurusWeb.ErrorHTML)
        |> render("404.html", page_title: "User not found")

      user ->
        # Check if profile is accessible
        auth_user = conn.assigns[:auth_user]

        if user.profile_public == true do
          # Public profile - redirect
          redirect(conn, to: ~p"/user/#{User.username_slug(user)}")
        else
          # Private profile - only redirect if viewing own profile
          if auth_user && auth_user.id == user.id do
            redirect(conn, to: ~p"/user/#{User.username_slug(user)}")
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
