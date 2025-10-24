defmodule EventasaurusWeb.Admin.SourceStatsController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.Admin.SourceStatsCollector
  alias EventasaurusDiscovery.Sources.SourceRegistry

  @doc """
  GET /api/admin/stats/source/:source_slug

  Returns comprehensive statistics for a discovery source including:
  - Occurrence type distribution
  - Category breakdown
  - Translation coverage
  - Image statistics
  - Venue information

  ## Response Format
  ```json
  {
    "source": "sortiraparis",
    "timestamp": "2025-10-19T12:00:00Z",
    "stats": {
      "occurrence_types": [...],
      "category_stats": {...},
      "top_categories": [...],
      "translation_coverage": {...},
      "image_stats": {...},
      "venue_stats": {...}
    }
  }
  ```

  ## Error Responses
  - 403: Forbidden (non-admin user)
  - 404: Source not found
  - 500: Internal server error
  """
  def show(conn, %{"source_slug" => source_slug}) do
    # Verify admin access using email whitelist
    if is_admin_email?(conn) do
      # Verify source exists
      case SourceRegistry.get_sync_job(source_slug) do
        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{
            error: "Source not found",
            source: source_slug,
            message: "The requested source does not exist in the registry"
          })

        {:ok, _} ->
          # Get comprehensive stats
          stats = SourceStatsCollector.get_comprehensive_stats(source_slug)

          # Return successful response
          conn
          |> put_resp_header("cache-control", "public, max-age=300")
          |> json(%{
            source: source_slug,
            timestamp: DateTime.utc_now(),
            stats: stats
          })
      end
    else
      # Not an admin user
      conn
      |> put_status(:forbidden)
      |> json(%{
        error: "Admin access required",
        message: "This endpoint requires administrator privileges"
      })
    end
  rescue
    error ->
      require Logger

      Logger.error("""
      Error fetching stats for source #{source_slug}:
      #{inspect(error)}
      #{inspect(__STACKTRACE__)}
      """)

      conn
      |> put_status(:internal_server_error)
      |> json(%{
        error: "Internal server error",
        message: "An error occurred while fetching stats for this source"
      })
  end

  # Check if the current user's email is in the admin email list
  defp is_admin_email?(conn) do
    admin_emails = get_admin_emails()
    current_user = conn.assigns[:current_user] || conn.assigns[:user]

    # Only check if we have both admin emails configured and a logged-in user
    admin_emails != [] && current_user && current_user.email &&
      String.downcase(current_user.email) in admin_emails
  end

  # Parse the ADMIN_EMAILS environment variable into a list
  defp get_admin_emails do
    case System.get_env("ADMIN_EMAILS") do
      nil ->
        []

      "" ->
        []

      emails ->
        emails
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.downcase/1)
        |> Enum.filter(&(&1 != ""))
    end
  end
end
