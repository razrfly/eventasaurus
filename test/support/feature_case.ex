defmodule EventasaurusWeb.FeatureCase do
  @moduledoc """
  This module defines the test case to be used by end-to-end tests using Wallaby.

  Such tests rely on `Wallaby.Feature` and `Phoenix.LiveViewTest` for
  running browser automation tests that interact with the application as a user would.
  """

  use ExUnit.CaseTemplate
  import EventasaurusApp.Factory

  using do
    quote do
      # Import conveniences for testing with connections
      use Wallaby.Feature

      # Import our factory and auth helpers
      import EventasaurusApp.Factory
      import Wallaby.Query, only: [text_field: 1, button: 1]
      import Wallaby.Browser

      # The default endpoint for testing
      @endpoint EventasaurusWeb.Endpoint

      # Helper function to create and authenticate a user in browser tests
      def create_and_login_user(session) do
        user = insert(:user)

        # Visit login page and authenticate
        updated_session =
          session
          |> visit("/auth/login")
          |> fill_in(text_field("Email"), with: user.email)
          |> click(button("Log In"))

        {updated_session, user}
      end

      # Helper function to create an event with an organizer
      def create_event_with_organizer() do
        user = insert(:user)
        event = insert(:event)
        # Create the relationship between user and event
        insert(:event_user, event: event, user: user)
        {event, user}
      end

      # Helper to clean up test auth state
      def clear_browser_auth(session) do
        session
        |> visit("/auth/logout")
        |> assert_has(Wallaby.Query.text("Logout Successful"))
      end
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EventasaurusApp.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(EventasaurusApp.Repo, {:shared, self()})
    end

    # Start a Wallaby session for browser tests
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(EventasaurusApp.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    %{session: session}
  end
end
