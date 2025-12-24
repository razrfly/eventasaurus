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
            auth_user = conn.assigns[:auth_user]

            # Ensure we have a proper User struct for mutual events query
            viewer_user =
              case auth_user do
                %User{} = u -> u
                %{id: id} when is_integer(id) -> Accounts.get_user(id)
                _ -> nil
              end

            # Get profile data - filter to public events only for public profiles
            stats = Accounts.get_user_event_stats(user)
            recent_events = Accounts.get_user_recent_events(user, limit: 10, public_only: true)

            # Get mutual events if user is logged in and different from profile user
            mutual_events =
              if viewer_user && viewer_user.id != user.id do
                Accounts.get_mutual_events(viewer_user, user, limit: 6)
              else
                []
              end

            conn
            |> assign(:profile_user, user)
            |> assign(:page_title, "#{User.display_name(user)} (@#{canonical_username})")
            |> assign(:stats, stats)
            |> assign(:recent_events, recent_events)
            |> assign(:mutual_events, mutual_events)
            |> assign(:is_own_profile, false)
            |> render(:show)
          else
            # Private profile - check if it's the current user viewing their own profile
            auth_user = conn.assigns[:auth_user]

            if auth_user && auth_user.id == user.id do
              # User viewing their own private profile - show all events
              stats = Accounts.get_user_event_stats(user)
              recent_events = Accounts.get_user_recent_events(user, limit: 10, public_only: false)

              conn
              |> assign(:profile_user, user)
              |> assign(:page_title, "Your Profile (@#{canonical_username})")
              |> assign(:stats, stats)
              |> assign(:recent_events, recent_events)
              |> assign(:mutual_events, [])
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

  @doc """
  Redirect legacy /user/:username URLs to new /users/:username format

  This provides backward compatibility for old bookmarks and shared links.
  """
  def redirect_legacy(conn, %{"username" => username}) do
    redirect(conn, to: ~p"/users/#{username}")
  end
end
