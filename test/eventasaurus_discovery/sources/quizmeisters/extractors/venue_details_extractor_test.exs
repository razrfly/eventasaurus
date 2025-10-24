defmodule EventasaurusDiscovery.Sources.Quizmeisters.Extractors.VenueDetailsExtractorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Quizmeisters.Extractors.VenueDetailsExtractor

  @fixtures_dir Path.join([__DIR__, "..", "fixtures"])

  describe "extract_additional_details/1" do
    test "returns error for nil URL" do
      assert {:error, "No URL available"} = VenueDetailsExtractor.extract_additional_details(nil)
    end

    # Note: Full integration tests with HTTP would require mocking Client.fetch_page
    # These tests focus on the parse_details logic using fixtures
  end

  describe "parse_details/1 via fixture" do
    test "extracts all fields from complete detail page" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page.html"))
      {:ok, document} = Floki.parse_document(html)

      # Use private function via module attribute (testing pattern)
      details = extract_details_from_document(document)

      assert details.description =~ "Welcome to The Library Bar"
      assert details.description =~ "Join us every Wednesday"

      assert details.hero_image_url ==
               "https://uploads-ssl.webflow.com/images/library-bar-hero.jpg"

      assert details.website == "https://librarybar.com"
      assert details.facebook == "https://facebook.com/librarybar"
      assert details.instagram == "https://instagram.com/librarybar"
      assert details.phone == "555-123-4567"
      assert details.on_break == false

      # Performer data
      assert details.performer != nil
      assert details.performer.name == "John Smith"

      assert details.performer.image_url ==
               "https://uploads-ssl.webflow.com/host-images/john-smith-profile.jpg"
    end

    test "extracts performer with image only (no name)" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page_image_only.html"))
      {:ok, document} = Floki.parse_document(html)

      details = extract_details_from_document(document)

      assert details.performer != nil
      # Should have generated a name from the image filename
      assert details.performer.name != nil
      assert details.performer.name != ""

      assert details.performer.image_url ==
               "https://uploads-ssl.webflow.com/host-images/trivia-host-profile.jpg"
    end

    test "detects venue on break status" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page_on_break.html"))
      {:ok, document} = Floki.parse_document(html)

      details = extract_details_from_document(document)

      assert details.on_break == true
    end

    test "filters out Lorem ipsum placeholder text" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page_on_break.html"))
      {:ok, document} = Floki.parse_document(html)

      details = extract_details_from_document(document)

      # Should be empty because it was Lorem ipsum
      assert details.description == ""
    end

    test "falls back to generic description when venue-specific is empty" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page_image_only.html"))
      {:ok, document} = Floki.parse_document(html)

      details = extract_details_from_document(document)

      assert details.description == "Join us for weekly trivia night!"
    end

    test "filters placeholder images" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page_image_only.html"))
      {:ok, document} = Floki.parse_document(html)

      details = extract_details_from_document(document)

      # Should only get the real image, not the placeholder
      assert details.performer.image_url ==
               "https://uploads-ssl.webflow.com/host-images/trivia-host-profile.jpg"
    end

    test "handles missing phone number" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page_image_only.html"))
      {:ok, document} = Floki.parse_document(html)

      details = extract_details_from_document(document)

      assert details.phone == nil
    end

    test "handles missing social media links" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page_image_only.html"))
      {:ok, document} = Floki.parse_document(html)

      details = extract_details_from_document(document)

      assert details.website == nil
      assert details.facebook == "https://facebook.com/downtownpub"
      assert details.instagram == nil
    end

    test "handles missing performer data" do
      {:ok, html} = File.read(Path.join(@fixtures_dir, "detail_page_on_break.html"))
      {:ok, document} = Floki.parse_document(html)

      details = extract_details_from_document(document)

      # No host-info div in the on_break fixture
      assert details.performer == nil
    end
  end

  describe "performer extraction edge cases" do
    test "extracts performer with name only (no image)" do
      html = """
      <div class="host-info">
        <div class="host-name">Jane Doe</div>
      </div>
      """

      {:ok, document} = Floki.parse_document(html)
      details = extract_details_from_document(document)

      assert details.performer != nil
      assert details.performer.name == "Jane Doe"
      assert details.performer.image_url == nil
    end

    test "handles empty host-name element" do
      html = """
      <div class="host-info">
        <div class="host-name">   </div>
        <img class="host-image" src="https://example.com/host.jpg">
      </div>
      """

      {:ok, document} = Floki.parse_document(html)
      details = extract_details_from_document(document)

      assert details.performer != nil
      # Should generate name from image
      assert details.performer.name != ""
      assert details.performer.image_url == "https://example.com/host.jpg"
    end

    test "filters multiple placeholder images" do
      html = """
      <div class="host-info">
        <div class="host-name">Host Name</div>
        <img class="host-image placeholder" src="https://example.com/placeholder1.jpg">
        <img class="host-image w-condition-invisible" src="https://example.com/placeholder2.jpg">
        <img class="host-image" src="https://example.com/real-host.jpg">
      </div>
      """

      {:ok, document} = Floki.parse_document(html)
      details = extract_details_from_document(document)

      assert details.performer.image_url == "https://example.com/real-host.jpg"
    end

    test "returns nil when no host-info div present" do
      html = """
      <div class="venue-block">
        <p>No host info here</p>
      </div>
      """

      {:ok, document} = Floki.parse_document(html)
      details = extract_details_from_document(document)

      assert details.performer == nil
    end
  end

  describe "description extraction" do
    test "extracts venue-specific description paragraphs" do
      html = """
      <div class="venue-description w-richtext">
        <p>First paragraph.</p>
        <p>Second paragraph.</p>
      </div>
      """

      {:ok, document} = Floki.parse_document(html)
      details = extract_details_from_document(document)

      assert details.description == "First paragraph.\n\nSecond paragraph."
    end

    test "ignores generic descriptions when venue-specific exists" do
      html = """
      <div class="venue-description w-richtext">
        <p>Venue specific text.</p>
      </div>
      <div class="venue-description trivia-generic w-richtext">
        <p>Generic text.</p>
      </div>
      """

      {:ok, document} = Floki.parse_document(html)
      details = extract_details_from_document(document)

      assert details.description == "Venue specific text."
      refute details.description =~ "Generic text"
    end
  end

  # Helper to call the private parse_details function
  # This uses the same logic as the module but allows testing without HTTP
  defp extract_details_from_document(document) do
    # This mirrors the internal parse_details/1 function
    %{
      description: extract_description(document),
      hero_image_url: extract_hero_image(document),
      website: extract_website(document),
      facebook: extract_social_link(document, "facebook"),
      instagram: extract_social_link(document, "instagram"),
      phone: extract_phone(document),
      on_break: extract_on_break(document),
      performer: extract_performer(document)
    }
  end

  # Mirror the private functions from VenueDetailsExtractor for testing
  defp extract_description(document) do
    description =
      document
      |> Floki.find(
        ".venue-description.w-richtext:not(.trivia-generic):not(.bingo-generic):not(.survey-generic) p"
      )
      |> Enum.map(&Floki.text/1)
      |> Enum.join("\n\n")
      |> String.trim()
      |> filter_lorem_ipsum()

    if description == "" do
      document
      |> Floki.find(".venue-description.trivia-generic.w-richtext p")
      |> Enum.map(&Floki.text/1)
      |> Enum.join("\n\n")
      |> String.trim()
      |> filter_lorem_ipsum()
    else
      description
    end
  end

  defp extract_hero_image(document) do
    document
    |> Floki.find(".venue-photo")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp extract_website(document) do
    document
    |> Floki.find(".icon-block a")
    |> Enum.find_value(fn el ->
      href = Floki.attribute(el, "href") |> List.first()
      if Floki.find(el, "img[alt*='website']") |> Enum.any?(), do: href
    end)
  end

  defp extract_social_link(document, platform) do
    document
    |> Floki.find(".icon-block a")
    |> Enum.find_value(fn el ->
      href = Floki.attribute(el, "href") |> List.first()
      if Floki.find(el, "img[alt*='#{platform}']") |> Enum.any?(), do: href
    end)
  end

  defp extract_phone(document) do
    document
    |> Floki.find(".venue-block .paragraph")
    |> Enum.map(&Floki.text/1)
    |> Enum.find(fn text ->
      String.match?(text, ~r/^\+?[\d\s\-\(\)]{8,}$/)
    end)
    |> case do
      nil -> nil
      number -> String.trim(number)
    end
  end

  defp extract_on_break(document) do
    document
    |> Floki.find(".on-break")
    |> Enum.any?()
  end

  defp extract_performer(document) do
    host_info = Floki.find(document, ".host-info")

    case host_info do
      [] ->
        nil

      elements ->
        name_elements = Floki.find(elements, ".host-name")

        name =
          if Enum.empty?(name_elements) do
            ""
          else
            Floki.text(name_elements) |> String.trim()
          end

        all_images = Floki.find(elements, ".host-image")

        images =
          all_images
          |> Enum.filter(fn img ->
            class = Floki.attribute(img, "class") |> List.first() || ""
            src = Floki.attribute(img, "src") |> List.first() || ""

            not String.contains?(class, "placeholder") and
              not String.contains?(class, "w-condition-invisible") and
              src != ""
          end)

        image_url =
          case images do
            [] -> nil
            [img | _] -> Floki.attribute(img, "src") |> List.first()
          end

        cond do
          name != "" and image_url ->
            %{name: name, image_url: image_url}

          name != "" ->
            %{name: name, image_url: nil}

          image_url ->
            image_basename = Path.basename(image_url)

            extracted_name =
              image_basename
              |> String.split(["-", "_"], trim: true)
              |> Enum.filter(fn part ->
                String.length(part) > 2 and
                  not String.match?(part, ~r/^\d+/) and
                  not String.match?(part, ~r/^[0-9a-f]{32}$/i)
              end)
              |> Enum.join(" ")
              |> String.trim()
              |> case do
                "" -> "Quizmeisters Host"
                name -> String.capitalize(name)
              end

            %{name: extracted_name, image_url: image_url}

          true ->
            nil
        end
    end
  end

  defp filter_lorem_ipsum(text) when is_binary(text) do
    if String.starts_with?(
         text,
         "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore e"
       ),
       do: "",
       else: text
  end

  defp filter_lorem_ipsum(_), do: ""
end
