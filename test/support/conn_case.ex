defmodule EventasaurusWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use EventasaurusWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint EventasaurusWeb.Endpoint

      use EventasaurusWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import EventasaurusWeb.ConnCase
      import EventasaurusApp.Factory
    end
  end

  setup tags do
    EventasaurusApp.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Authenticates a user for testing by setting up the session.

  With Clerk authentication, we simply set the user_id in the session,
  which is what ClerkAuthPlug stores after authenticating a user.

  ## Usage

      user = insert(:user)
      conn = log_in_user(conn, user)

  ## Returns

  An updated conn with the user authenticated in the session.
  """
  def log_in_user(conn, user) do
    # With Clerk, the session stores the current_user_id
    # which is the local database user ID
    conn
    |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
    |> Plug.Conn.assign(:current_user, user)
    |> Plug.Conn.assign(:auth_user, user)
  end

  @doc """
  Creates and authenticates a test user in one step.

  ## Usage

      {conn, user} = register_and_log_in_user(conn)
      # or with custom attributes
      {conn, user} = register_and_log_in_user(conn, %{name: "Custom Name"})

  ## Returns

  A tuple with the updated conn and the created user.
  """
  def register_and_log_in_user(conn, attrs \\ %{}) do
    user = EventasaurusApp.Factory.insert(:user, attrs)
    {log_in_user(conn, user), user}
  end

  @doc """
  Clears test authentication data to prevent interference between tests.

  With Clerk authentication, this is no longer needed as we don't use
  a test client. The sandbox handles cleanup between tests.

  ## Usage

      setup do
        clear_test_auth()
        :ok
      end
  """
  def clear_test_auth do
    # No-op with Clerk authentication
    # The Ecto sandbox handles cleanup between tests
    :ok
  end

  @doc """
  Creates an authenticated user as an organizer for the given event.

  ## Usage

      event = insert(:event)
      {conn, user} = log_in_event_organizer(conn, event)

  ## Returns

  A tuple with the authenticated conn and the organizer user.
  """
  def log_in_event_organizer(conn, event, user_attrs \\ %{}) do
    user = EventasaurusApp.Factory.insert(:user, user_attrs)
    # Add user as organizer to the event
    EventasaurusApp.Factory.insert(:event_user, event: event, user: user, role: "organizer")
    {log_in_user(conn, user), user}
  end
end
