defmodule EventasaurusWeb.PageController do
  use EventasaurusWeb, :controller

  require Logger

  alias Eventasaurus.Sanity.Changelog
  alias Eventasaurus.Sanity.Roadmap

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip using the default app layout.
    render(conn, :home, layout: false)
  end

  def index(conn, _params) do
    render(conn, :index)
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def about_v2(conn, _params) do
    render(conn, :about_v2)
  end

  def about_v3(conn, _params) do
    render(conn, :about_v3)
  end

  def our_story(conn, _params) do
    render(conn, :our_story)
  end

  def whats_new(conn, _params) do
    render(conn, :whats_new)
  end

  def components(conn, _params) do
    render(conn, :components)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def your_data(conn, _params) do
    render(conn, :your_data)
  end

  def terms(conn, _params) do
    render(conn, :terms)
  end

  def pitch(conn, _params) do
    render(conn, :pitch)
  end

  def pitch2(conn, _params) do
    render(conn, :pitch2)
  end

  def crypto_pitch(conn, _params) do
    render(conn, :crypto_pitch)
  end

  def invite_only(conn, _params) do
    render(conn, :invite_only)
  end

  def how_it_works(conn, _params) do
    render(conn, :how_it_works)
  end

  def manifesto(conn, _params) do
    render(conn, :manifesto)
  end

  def redirect_to_auth_login(conn, _params) do
    # Preserve query parameters when redirecting
    query_string = conn.query_string

    path =
      if query_string != "" do
        "/auth/login?" <> query_string
      else
        "/auth/login"
      end

    redirect(conn, to: path)
  end

  def redirect_to_auth_register(conn, _params) do
    # Preserve query parameters when redirecting
    query_string = conn.query_string

    path =
      if query_string != "" do
        "/auth/register?" <> query_string
      else
        "/auth/register"
      end

    redirect(conn, to: path)
  end

  def redirect_to_auth_register_with_event(conn, %{"event_id" => event_id}) do
    # Redirect to auth register with event_id parameter
    query_string = conn.query_string
    event_param = "event_id=#{URI.encode_www_form(event_id)}"

    path =
      if query_string != "" do
        "/auth/register?#{event_param}&#{query_string}"
      else
        "/auth/register?#{event_param}"
      end

    redirect(conn, to: path)
  end

  def redirect_to_invite_only(conn, _params) do
    # Direct signup attempts (without event_id) should go to invite-only page
    redirect(conn, to: "/invite-only")
  end

  def changelog(conn, params) do
    page = parse_page(params["page"])

    case Changelog.list_entries(page: page) do
      {:ok, entries, pagination} ->
        render(conn, :changelog, entries: entries, pagination: pagination)

      {:error, reason} ->
        Logger.warning("Failed to fetch changelog from Sanity: #{inspect(reason)}")

        render(conn, :changelog,
          entries: fallback_changelog_entries(),
          pagination: fallback_pagination()
        )
    end
  end

  defp parse_page(nil), do: 1

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {num, _} when num > 0 -> num
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp fallback_pagination do
    %{
      page: 1,
      page_size: 10,
      total_entries: 1,
      total_pages: 1,
      has_next: false,
      has_prev: false
    }
  end

  # Fallback entries for when Sanity is unavailable
  defp fallback_changelog_entries do
    [
      %{
        id: "fallback-1",
        date: "December 8, 2024",
        iso_date: "2024-12-08",
        title: "Changelog Temporarily Unavailable",
        summary: "We're having trouble loading the changelog. Please try again later.",
        changes: [
          %{type: "changed", description: "Full changelog will be available shortly"}
        ],
        image: nil
      }
    ]
  end

  def changelog_beta(conn, _params) do
    render(conn, :changelog_beta, roadmap_items: mock_changelog_beta_items())
  end

  def roadmap(conn, _params) do
    case Roadmap.list_entries() do
      {:ok, %{now: now_items, next: next_items, later: later_items}} ->
        render(conn, :roadmap,
          now_items: now_items,
          next_items: next_items,
          later_items: later_items
        )

      {:error, reason} ->
        Logger.warning("Failed to fetch roadmap from Sanity: #{inspect(reason)}")
        # Fall back to mock data
        {now_items, next_items, later_items} = mock_roadmap_items()

        render(conn, :roadmap,
          now_items: now_items,
          next_items: next_items,
          later_items: later_items
        )
    end
  end

  defp mock_roadmap_items do
    # Uses simpler structure matching RoadmapComponents style
    # with status pill (In Progress, Planned, Research, Concept) and colorful tags
    now_items = [
      %{
        id: 1,
        title: "Enhanced User Profiles",
        description:
          "Totally revamped user profiles with customizable themes, pinned events, and improved social sharing capabilities.",
        status: "In Progress",
        tags: ["Social", "Design"]
      },
      %{
        id: 2,
        title: "Advanced Event Analytics",
        description:
          "Deep dive into your event performance with real-time stats, attendee demographics, and engagement metrics.",
        status: "In Progress",
        tags: ["Analytics", "Business"]
      },
      %{
        id: 3,
        title: "Real-time Notifications",
        description:
          "Never miss an event again. Get push notifications for events you're interested in, including price drops and new dates.",
        status: "Planned",
        tags: ["Mobile", "Notifications"]
      }
    ]

    next_items = [
      %{
        id: 4,
        title: "Native Mobile App",
        description:
          "A dedicated mobile experience for iOS and Android, bringing Eventasaurus to your pocket with offline mode.",
        status: "Research",
        tags: ["Mobile", "Platform"]
      },
      %{
        id: 5,
        title: "API v2 Public Access",
        description:
          "Opening up our robust API for third-party developers to build amazing integrations and tools.",
        status: "Planned",
        tags: ["API", "DevTools"]
      },
      %{
        id: 6,
        title: "Calendar Integrations",
        description:
          "Two-way sync with Google Calendar, Apple Calendar, and Outlook. Events you RSVP to automatically appear.",
        status: "Planned",
        tags: ["API", "Infrastructure"]
      }
    ]

    later_items = [
      %{
        id: 7,
        title: "AI-Powered Event Recommendations",
        description:
          "Smart suggestions based on your interests and past attendance to help you discover the perfect events.",
        status: "Concept",
        tags: ["AI", "Discovery"]
      },
      %{
        id: 8,
        title: "Group Event Planning",
        description:
          "Coordinate events with friends. Create polls to decide on dates, vote on venues, and split costs.",
        status: "Concept",
        tags: ["Social", "Groups"]
      },
      %{
        id: 9,
        title: "Accessibility Improvements",
        description:
          "Enhanced screen reader support, keyboard navigation, and color contrast options for everyone.",
        status: "Research",
        tags: ["Accessibility", "UX"]
      }
    ]

    {now_items, next_items, later_items}
  end

  defp mock_changelog_beta_items do
    [
      %{
        quarter: "Q1 2026",
        status: "current",
        features: [
          %{
            id: 1,
            title: "Enhanced User Profiles",
            description:
              "Totally revamped user profiles with customizable themes, pinned events, and improved social sharing capabilities.",
            status: "In Progress",
            tags: ["Social", "Design"]
          },
          %{
            id: 2,
            title: "Advanced Event Analytics",
            description:
              "Deep dive into your event performance with real-time stats, attendee demographics, and engagement metrics.",
            status: "Planned",
            tags: ["Analytics", "Business"]
          }
        ]
      },
      %{
        quarter: "Q2 2026",
        status: "upcoming",
        features: [
          %{
            id: 3,
            title: "Native Mobile App",
            description:
              "A dedicated mobile experience for iOS and Android, bringing Eventasaurus to your pocket with offline mode.",
            status: "Research",
            tags: ["Mobile", "Platform"]
          },
          %{
            id: 4,
            title: "API v2 Public Access",
            description:
              "Opening up our robust API for third-party developers to build amazing integrations and tools.",
            status: "Planned",
            tags: ["API", "DevTools"]
          }
        ]
      },
      %{
        quarter: "Future",
        status: "future",
        features: [
          %{
            id: 5,
            title: "AI-Powered Event Recommendations",
            description:
              "Smart suggestions based on your interests and past attendance to help you discover the perfect events.",
            status: "Concept",
            tags: ["AI", "Discovery"]
          }
        ]
      }
    ]
  end

  def eventasaurus_redirect(conn, _params) do
    render(conn, :eventasaurus, layout: false)
  end

  def sitemap_redirect(conn, params) do
    # Redirect all sitemap requests to R2 CDN
    # Uses configuration from :eventasaurus, :r2
    r2_config = Application.get_env(:eventasaurus, :r2) || %{}
    cdn_url = r2_config[:cdn_url] || System.get_env("R2_CDN_URL") || "https://cdn2.wombie.com"

    # Determine the sitemap file to serve
    requested_path =
      case params do
        %{"path" => path_parts} when is_list(path_parts) ->
          # /sitemaps/* - serve the exact file requested (e.g., sitemap-00001.xml.gz)
          "sitemaps/" <> Enum.join(path_parts, "/")

        _ ->
          # /sitemap or /sitemap.xml - serve the main sitemap index file
          "sitemaps/sitemap.xml.gz"
      end

    storage_url = "#{cdn_url}/#{requested_path}"
    redirect(conn, external: storage_url)
  end
end
