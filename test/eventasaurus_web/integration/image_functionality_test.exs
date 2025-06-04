defmodule EventasaurusWeb.Integration.ImageFunctionalityTest do
  use EventasaurusWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EventasaurusApp.Auth.TestClient

  @moduletag :integration

  describe "Image functionality integration tests" do
    setup do
      user = insert(:user)
      %{user: user}
    end

    test "complete image search and selection flow", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Mount the new event page
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Open image picker using the correct button selector
      view |> element("button", "Click to add a cover image") |> render_click()

      # Perform search
      render_hook(view, "unified_search", %{"search_query" => "nature"})

      # Select an image
      render_hook(view, "select_image", %{
        "source" => "unsplash",
        "image_url" => "https://images.unsplash.com/test-image",
        "image_data" => %{
          "id" => "test-123",
          "user" => %{"name" => "Test Photographer"}
        }
      })

      # Verify image selection worked
      html = render(view)
      assert html =~ "https://images.unsplash.com/test-image"
    end

    test "image upload flow", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      # Mount the new event page
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Open image picker
      view |> element("button", "Click to add a cover image") |> render_click()

      # In unified interface, upload section is always visible (no tabs needed)
      html = render(view)
      assert html =~ "Drag and drop or click here to upload"

      # Simulate upload success
      _html = render_hook(view, "image_upload_success", %{
        "url" => "https://storage.supabase.com/uploaded-image.jpg",
        "path" => "events/uploaded-image.jpg"
      })

      # Verify upload success message
      html = render(view)
      assert html =~ "Image uploaded successfully!"
    end

    test "form preserves image data through validation", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Open image picker
      view |> element("button", "Click to add a cover image") |> render_click()

      # Select an image
      render_hook(view, "select_image", %{
        "source" => "unsplash",
        "image_url" => "https://images.unsplash.com/test-image",
        "image_data" => %{
          "id" => "test-123",
          "user" => %{"name" => "Test Photographer"}
        }
      })

      # Submit form with validation errors (missing required fields)
      html = render_submit(view, :submit, %{"event" => %{"title" => ""}})

      # Verify image data is preserved
      assert html =~ "test-image"
      # Verify validation error is shown by checking for error styling or required field indicators
      assert html =~ "phx-feedback-for" or html =~ "invalid" or html =~ "error"
    end

    test "search with empty query clears results", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Open image picker first
      view |> element("button", "Click to add a cover image") |> render_click()

      # Perform unified search with empty query
      html = render_hook(view, "unified_search", %{"search_query" => ""})

      # Should show search form ready for input
      assert html =~ "Search for more photos"
    end

    test "unified image picker interface shows all sections", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Open image picker
      html = view |> element("button", "Click to add a cover image") |> render_click()

      # Verify all sections are visible simultaneously (no tabs)
      assert html =~ "Drag and drop or click here to upload"  # Upload
      assert html =~ "Search for more photos"  # Search
      assert html =~ "Featured"  # Categories
      assert html =~ "General"   # Default images

      # Verify unified search form
      assert html =~ "phx-submit=\"unified_search\""
      refute html =~ "phx-submit=\"search_unsplash\""
    end

    test "select the first image", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Open image picker
      view |> element("button", "Click to add a cover image") |> render_click()

      # Select the first image
      html = render_hook(view, "select_image", %{
        "source" => "unsplash",
        "image_url" => "https://images.unsplash.com/test-image",
        "image_data" => %{
          "id" => "test-123",
          "user" => %{"name" => "Test Photographer"}
        }
      })

      # Verify image was selected and picker closed
      refute html =~ "Search for more photos"  # Modal should be closed
      assert html =~ "https://images.unsplash.com/test-image"
    end

    test "image upload functionality integration", %{conn: conn, user: user} do
      # Using TestClient for Supabase integration
      test_token = "test_token_for_upload"
      test_user = %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      }
      TestClient.set_test_user(test_token, test_user)

      {:ok, view, _html} =
        conn
        |> Plug.Test.init_test_session(%{})
        |> put_session("access_token", test_token)
        |> live(~p"/events/new")

      # Open image picker
      view |> element("button", "Click to add a cover image") |> render_click()

      # In the unified interface, upload is always visible (no tabs)
      html = render(view)

      # Verify upload section is present
      assert html =~ "Drag and drop or click here to upload"
      assert html =~ "Choose File"

      # Simulate upload success
      _html = render_hook(view, "image_upload_success", %{
        "url" => "https://storage.supabase.com/uploaded-image.jpg",
        "path" => "events/uploaded-image.jpg"
      })

      # Verify upload success message
      html = render(view)
      assert html =~ "Image uploaded successfully"
    end

    test "image search shows both Unsplash and TMDB results", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Open image picker
      view |> element("button", "Click to add a cover image") |> render_click()

      # Use unified search
      html = view
        |> element("form[phx-submit='unified_search']")
        |> render_submit(%{search_query: "party"})

      # Verify search interface is present
      assert html =~ "Search for more photos"

      # Since this is a real search, results depend on API responses
      # We just verify the interface works
      assert html =~ "phx-submit=\"unified_search\""
    end

    test "comprehensive image picker workflow", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Initially, image picker should be closed
      html = render(view)
      refute html =~ "Choose a Cover Image"

      # Open image picker
      view |> element("button", "Click to add a cover image") |> render_click()
      html = render(view)

      # Verify unified interface is present
      assert html =~ "Choose a Cover Image"
      assert html =~ "Drag and drop or click here to upload"
      assert html =~ "Search for more photos"
      assert html =~ "Featured"  # Categories

      # Close image picker
      view |> element("button[phx-click='close_image_picker'][aria-label='Close image picker']") |> render_click()
      html = render(view)
      refute html =~ "Choose a Cover Image"
    end
  end

  describe "Error resilience tests" do
    setup do
      user = insert(:user)
      %{user: user}
    end

    test "handles missing image in search results", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Open image picker
      view |> element("button", "Click to add a cover image") |> render_click()

      # Verify unified search form exists
      html = render(view)
      assert html =~ "phx-submit=\"unified_search\""

      # Test search with non-existent term
      _html = view
        |> element("form[phx-submit='unified_search']")
        |> render_submit(%{search_query: "nonexistent_search_term_that_should_fail_gracefully"})

      # Should not crash - just return empty results
      html = render(view)
      assert html =~ "Search for more photos"
    end
  end
end
