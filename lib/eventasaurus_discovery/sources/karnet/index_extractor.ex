defmodule EventasaurusDiscovery.Sources.Karnet.IndexExtractor do
  @moduledoc """
  Extracts event listings from Karnet Kraków index pages.

  Parses HTML to extract:
  - Event URLs
  - Event titles
  - Dates/times
  - Venues
  - Categories
  - Basic metadata
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Karnet.Config

  @doc """
  Extract all events from a list of index page HTML bodies.
  Returns a list of event data maps.
  """
  def extract_events_from_pages(pages) when is_list(pages) do
    pages
    |> Enum.flat_map(fn {page_num, html} ->
      Logger.debug("📄 Extracting events from page #{page_num}")
      extract_events_from_html(html)
    end)
  end

  @doc """
  Extract events from a single HTML page.
  """
  def extract_events_from_html(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        events = extract_event_cards(document)
        Logger.info("📊 Extracted #{length(events)} events from page")
        events

      {:error, reason} ->
        Logger.error("Failed to parse HTML: #{inspect(reason)}")
        []
    end
  end

  defp extract_event_cards(document) do
    # Try multiple possible selectors for event cards
    # The site structure might use different class names
    selectors = [
      ".event-item",
      ".wydarzenie",
      ".event-card",
      "article.event",
      "[data-event-id]",
      ".listing-item",
      # Common grid layout
      ".row .col-md-4",
      ".events-list .item"
    ]

    events =
      Enum.reduce_while(selectors, [], fn selector, _acc ->
        case Floki.find(document, selector) do
          [] ->
            {:cont, []}

          cards ->
            Logger.debug("Found #{length(cards)} events using selector: #{selector}")
            {:halt, cards}
        end
      end)

    # If no specific event cards found, try to find event links directly
    if events == [] do
      Logger.debug("No event cards found, extracting from links...")
      extract_events_from_links(document)
    else
      Enum.map(events, &extract_event_from_card/1)
      |> Enum.filter(&(&1 != nil))
    end
  end

  defp extract_event_from_card(card) do
    try do
      # Extract URL - using the actual structure from Karnet
      url =
        case Floki.find(card, "a.event-image, a.event-content") do
          [] ->
            nil

          links ->
            Floki.attribute(links, "href")
            |> List.first()
            |> case do
              nil -> nil
              href -> Config.build_event_url(href)
            end
        end

      if url do
        %{
          url: url,
          title: extract_title(card),
          date_text: extract_date_text(card),
          venue_name: extract_venue_name(card),
          category: extract_category(card),
          thumbnail_url: extract_thumbnail(card),
          description_snippet: extract_description(card),
          event_id: extract_event_id(card),
          extracted_at: DateTime.utc_now()
        }
      else
        nil
      end
    rescue
      e ->
        Logger.warning("Failed to extract event from card: #{inspect(e)}")
        nil
    end
  end

  defp extract_events_from_links(document) do
    # Find all links that look like event pages
    links = Floki.find(document, "a[href*='/wydarzenia/'], a[href*='/event/']")

    links
    |> Enum.map(fn link ->
      url = Floki.attribute(link, "href") |> List.first()
      title = Floki.text(link) |> String.trim()

      if url && String.length(title) > 3 && !String.contains?(url, "/page/") do
        # Try to find parent element for more context
        parent = find_parent_with_content(document, link)

        %{
          url: Config.build_event_url(url),
          title: title,
          date_text: extract_date_from_parent(parent),
          venue_name: extract_venue_from_parent(parent),
          category: extract_category_from_url(url),
          thumbnail_url: extract_thumbnail_from_parent(parent),
          description_snippet: extract_description_from_parent(parent),
          extracted_at: DateTime.utc_now()
        }
      else
        nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    # Remove duplicates
    |> Enum.uniq_by(& &1.url)
  end

  defp extract_title(card) do
    # For Karnet, title is in h3.event-title
    case Floki.find(card, "h3.event-title") do
      [] ->
        # Fallback to other selectors
        title_selectors = ["h2", "h3", ".title", "[class*='title']"]

        Enum.find_value(title_selectors, fn selector ->
          case Floki.find(card, selector) do
            [] ->
              nil

            elements ->
              Floki.text(elements)
              |> String.trim()
              |> case do
                "" -> nil
                text -> text
              end
          end
        end) || "Untitled Event"

      elements ->
        Floki.text(elements)
        |> String.trim()
        |> case do
          "" -> "Untitled Event"
          text -> text
        end
    end
  end

  defp extract_date_text(card) do
    # For Karnet, dates are typically in .event-date or similar elements
    date_selectors = [
      ".event-date",
      ".date",
      ".data",
      # "when" in Polish
      ".kiedy",
      ".event-meta time",
      "[class*='date']",
      "time",
      "[datetime]"
    ]

    Enum.find_value(date_selectors, fn selector ->
      case Floki.find(card, selector) do
        [] ->
          nil

        elements ->
          # Try to get datetime attribute first
          datetime = Floki.attribute(elements, "datetime") |> List.first()

          if datetime do
            datetime
          else
            Floki.text(elements)
            |> String.trim()
            |> case do
              "" -> nil
              text -> text
            end
          end
      end
    end)
  end

  defp extract_venue_name(card) do
    # For Karnet, venues might be in .event-location or similar
    venue_selectors = [
      ".event-location",
      ".event-venue",
      ".venue",
      ".location",
      # "place" in Polish
      ".miejsce",
      # "where" in Polish
      ".gdzie",
      "[class*='venue']",
      "[class*='location']"
    ]

    Enum.find_value(venue_selectors, fn selector ->
      case Floki.find(card, selector) do
        [] ->
          nil

        elements ->
          Floki.text(elements)
          |> String.trim()
          |> case do
            "" -> nil
            text -> text
          end
      end
    end)
  end

  defp extract_category(card) do
    # First try existing selectors
    category_selectors = [
      ".category",
      ".kategoria",
      ".event-type",
      ".typ",
      "[class*='category']",
      ".tag",
      ".label"
    ]

    category =
      Enum.find_value(category_selectors, fn selector ->
        case Floki.find(card, selector) do
          [] ->
            nil

          elements ->
            Floki.text(elements)
            |> String.trim()
            |> String.downcase()
            |> case do
              "" -> nil
              text -> text
            end
        end
      end)

    # NEW: If no category found, extract from event links within the card
    category =
      if is_nil(category) do
        links = Floki.find(card, "a[href*='/wydarzenia/']")

        Enum.find_value(links, fn link ->
          href = Floki.attribute([link], "href") |> List.first()
          extract_category_from_wydarzenia_url(href)
        end)
      else
        category
      end

    category
  end

  defp extract_category_from_wydarzenia_url(nil), do: nil

  defp extract_category_from_wydarzenia_url(url) when is_binary(url) do
    case Regex.run(~r{/wydarzenia/([^/,]+)}, url) do
      [_, category] -> String.trim(category) |> String.downcase()
      _ -> nil
    end
  end

  defp extract_thumbnail(card) do
    img_selectors = [
      "img",
      ".thumbnail img",
      ".event-image img",
      "[class*='image'] img"
    ]

    Enum.find_value(img_selectors, fn selector ->
      case Floki.find(card, selector) do
        [] ->
          nil

        imgs ->
          src = Floki.attribute(imgs, "src") |> List.first()

          if src do
            Config.build_event_url(src)
          else
            # Try data-src for lazy loading
            Floki.attribute(imgs, "data-src")
            |> List.first()
            |> case do
              nil -> nil
              data_src -> Config.build_event_url(data_src)
            end
          end
      end
    end)
  end

  defp extract_description(card) do
    desc_selectors = [
      ".description",
      # "description" in Polish
      ".opis",
      ".excerpt",
      ".summary",
      "p"
    ]

    Enum.find_value(desc_selectors, fn selector ->
      case Floki.find(card, selector) do
        [] ->
          nil

        elements ->
          Floki.text(elements)
          |> String.trim()
          # Limit to 200 chars
          |> String.slice(0, 200)
          |> case do
            "" -> nil
            text -> text
          end
      end
    end)
  end

  # Helper functions for extracting from parent elements
  defp find_parent_with_content(document, link) do
    # This is a simplified version - in reality, we'd need more sophisticated DOM traversal
    Floki.find(document, "div:has(> #{Floki.raw_html(link)})")
    |> List.first()
  end

  defp extract_date_from_parent(nil), do: nil

  defp extract_date_from_parent(parent) do
    extract_date_text(parent)
  end

  defp extract_venue_from_parent(nil), do: nil

  defp extract_venue_from_parent(parent) do
    extract_venue_name(parent)
  end

  defp extract_thumbnail_from_parent(nil), do: nil

  defp extract_thumbnail_from_parent(parent) do
    extract_thumbnail(parent)
  end

  defp extract_description_from_parent(nil), do: nil

  defp extract_description_from_parent(parent) do
    extract_description(parent)
  end

  defp extract_category_from_url(url) do
    # Try to extract category from URL pattern
    cond do
      String.contains?(url, "festiwal") -> "festival"
      String.contains?(url, "koncert") -> "concert"
      String.contains?(url, "spektakl") -> "performance"
      String.contains?(url, "wystawa") -> "exhibition"
      String.contains?(url, "film") -> "film"
      true -> nil
    end
  end

  defp extract_event_id(card) do
    # Extract from data-id attribute on the event-item div
    Floki.attribute(card, "data-id") |> List.first()
  end
end
