defmodule EventasaurusDiscovery.Sources.Pubquiz.DetailExtractor do
  @moduledoc """
  Extracts detailed information from PubQuiz.pl venue pages.

  Ported from trivia_advisor Extractor module with enhancements for schedule extraction.
  """

  @doc """
  Extracts venue details from HTML.

  Returns a map with description, address, phone, host, and schedule information.
  """
  def extract_venue_details(html) do
    doc = Floki.parse_document!(html)

    %{
      description: extract_description(doc),
      address: extract_address(doc),
      phone: extract_phone(doc),
      host: extract_host(doc),
      schedule: extract_schedule(doc)
    }
  end

  defp extract_description(doc) do
    doc
    |> Floki.find(".sec-text")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_address(doc) do
    doc
    |> Floki.find(".checklist li")
    |> Enum.find_value(fn element ->
      text = Floki.text(element)

      if String.contains?(text, "Adres:") do
        text
        |> String.replace(~r/^Adres:\s*/, "")
        |> String.trim()
      end
    end)
  end

  defp extract_phone(doc) do
    doc
    |> Floki.find(".checklist li")
    |> Enum.find_value(fn element ->
      text = Floki.text(element)

      if String.contains?(text, "Telefon:") do
        text
        |> String.replace(~r/^Telefon:\s*/, "")
        |> String.trim()
      end
    end)
  end

  defp extract_host(doc) do
    doc
    |> Floki.find(".checklist li")
    |> Enum.find_value(fn element ->
      text = Floki.text(element)

      if String.contains?(text, "Prowadząca:") ||
           String.contains?(text, "Prowadzący:") ||
           String.contains?(text, "Prowadzi:") do
        text
        |> String.replace(~r/^Prowadz[aąiy][cć]?[ay]?:\s*/, "")
        |> String.trim()
      end
    end)
  end

  defp extract_schedule(doc) do
    # Schedule Extraction Strategy
    #
    # PubQuiz.pl displays event schedules in two different HTML structures:
    #
    # 1. Tab Buttons (Most Reliable):
    #    <button id="wtorek" class="e-n-tab-title">
    #    - Day name is in the `id` attribute (e.g., "wtorek" = Tuesday)
    #    - Most consistent across different page layouts
    #    - Used as primary extraction method
    #
    # 2. Product Titles (Fallback):
    #    "2025.10.07 [WTOREK] MK Bowling 19:00"
    #    - Day name in brackets with time at the end
    #    - Used when tab structure is not present
    #    - Less reliable due to varying formats
    #
    # We try tab buttons first because they have a consistent structure, falling
    # back to product titles only if tabs aren't found. This handles different
    # page layouts and ensures we can extract schedules from all venue pages.

    # Try extracting from tab buttons first (most reliable)
    schedule_from_tabs =
      doc
      |> Floki.find(".e-n-tab-title")
      |> Enum.find_value(fn element ->
        # Get the id attribute which contains the day name
        case Floki.attribute(element, "id") do
          [day_id]
          when day_id in [
                 "poniedzialek",
                 "wtorek",
                 "sroda",
                 "czwartek",
                 "piatek",
                 "sobota",
                 "niedziela"
               ] ->
            # Found a valid day tab button
            # Now try to find the corresponding time in product titles
            extract_time_from_products(doc, day_id)

          _ ->
            nil
        end
      end)

    # Try extracting from product titles if tabs didn't work
    schedule_from_products =
      if schedule_from_tabs do
        nil
      else
        doc
        |> Floki.find(".product-title")
        |> Enum.find_value(fn element ->
          text = Floki.text(element)

          # Match pattern: [DAY_NAME] ... TIME
          # Example: "2025.10.07 [WTOREK] MK Bowling 19:00"
          case Regex.run(~r/\[([A-ZĄĆĘŁŃÓŚŹŻ]+)\].*?(\d{1,2}:\d{2})/i, text) do
            [_, day_bracket, time] ->
              day_normalized = String.downcase(day_bracket)
              "#{day_normalized} #{time}"

            _ ->
              nil
          end
        end)
      end

    schedule_from_tabs || schedule_from_products
  end

  defp extract_time_from_products(doc, day_id) do
    # Convert day_id to uppercase bracket format for matching
    day_bracket = String.upcase(day_id)

    doc
    |> Floki.find(".product-title")
    |> Enum.find_value(fn element ->
      text = Floki.text(element)

      # Look for [DAY_NAME] ... TIME pattern
      if String.contains?(text, "[#{day_bracket}]") do
        case Regex.run(~r/\[#{day_bracket}\].*?(\d{1,2}:\d{2})/, text) do
          [_, time] ->
            "#{day_id} #{time}"

          _ ->
            nil
        end
      end
    end)
  end
end
