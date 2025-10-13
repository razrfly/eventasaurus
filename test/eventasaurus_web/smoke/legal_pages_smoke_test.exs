defmodule EventasaurusWeb.Smoke.LegalPagesSmokeTest do
  use EventasaurusWeb.ConnCase, async: true

  # Helper to remove HTML comments and module names from content
  defp strip_internal_content(html) do
    html
    # Remove HTML comments
    |> String.replace(~r/<!--.*?-->/s, "")
    # Remove module name references like EventasaurusWeb
    |> String.replace(~r/Eventasaurus\w*\./s, "")
  end

  describe "Legal Pages - Phase 4 Rebranding Verification" do
    test "privacy page renders without Eventasaurus branding in visible content", %{conn: conn} do
      conn = get(conn, ~p"/privacy")
      assert html_response(conn, 200)
      html = html_response(conn, 200)
      visible_content = strip_internal_content(html)

      # Should have Wombie branding
      assert visible_content =~ "Wombie"
      assert visible_content =~ "wombie.com"

      # Should NOT have old Eventasaurus branding in visible content
      refute visible_content =~ "Eventasaurus"
      refute visible_content =~ "eventasaurus.com"
    end

    test "terms page renders without Eventasaurus branding in visible content", %{conn: conn} do
      conn = get(conn, ~p"/terms")
      assert html_response(conn, 200)
      html = html_response(conn, 200)
      visible_content = strip_internal_content(html)

      # Should have Wombie branding
      assert visible_content =~ "Wombie"

      # Should NOT have old Eventasaurus branding in visible content
      refute visible_content =~ "Eventasaurus"
      refute visible_content =~ "eventasaurus.com"
    end

    test "your-data page renders without Eventasaurus branding in visible content", %{conn: conn} do
      conn = get(conn, ~p"/your-data")
      assert html_response(conn, 200)
      html = html_response(conn, 200)
      visible_content = strip_internal_content(html)

      # Should have Wombie branding
      assert visible_content =~ "Wombie"
      assert visible_content =~ "wombie.com"

      # Should NOT have old Eventasaurus branding in visible content
      refute visible_content =~ "Eventasaurus"
      refute visible_content =~ "eventasaurus.com"
    end

    test "our-story page renders without Eventasaurus branding in visible content", %{conn: conn} do
      conn = get(conn, ~p"/our-story")
      assert html_response(conn, 200)
      html = html_response(conn, 200)
      visible_content = strip_internal_content(html)

      # Should have Wombie branding
      assert visible_content =~ "Wombie"

      # Should NOT have old Eventasaurus branding in visible content
      refute visible_content =~ "Eventasaurus"
    end
  end
end
