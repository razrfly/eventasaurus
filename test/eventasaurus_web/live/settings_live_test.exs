defmodule EventasaurusWeb.SettingsLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EventasaurusApp.Accounts

  setup %{conn: conn} do
    # Create a test user
    user_attrs = %{
      email: "test@example.com",
      name: "Test User"
    }

    {:ok, user} = Accounts.create_user(user_attrs)

    # Mock authentication by setting up the session
    conn = log_in_user(conn, user)

    %{conn: conn, user: user}
  end

  test "SettingsLive renders account tab", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/settings")

    assert html =~ "Settings"
    assert html =~ "Profile Information"
    assert html =~ "Full Name"
    assert html =~ "Email Address"
    assert html =~ "Social Media"
  end

  test "SettingsLive handles form validation", %{conn: conn, user: _user} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    # Test form validation
    view
    |> form("form", user: %{name: "", bio: String.duplicate("a", 501)})
    |> render_change()

    # Should show validation errors in the rendered content
    html = render(view)
    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    assert html =~ "must be 500 characters or less"
  end

  test "SettingsLive saves profile updates", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    # Fill out and submit the form
    view
    |> form("form", user: %{name: "Updated Name", bio: "Updated bio"})
    |> render_submit()

    # Should show success message
    assert render(view) =~ "Profile updated successfully"
  end
end
