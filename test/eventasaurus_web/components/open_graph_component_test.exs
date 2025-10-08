defmodule EventasaurusWeb.Components.OpenGraphComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EventasaurusWeb.Components.OpenGraphComponent

  describe "open_graph_tags/1" do
    test "renders all required Open Graph meta tags" do
      assigns = %{
        type: "event",
        title: "Test Event",
        description: "This is a test event description",
        image_url: "https://example.com/image.jpg",
        image_width: 1200,
        image_height: 630,
        url: "https://example.com/events/test",
        site_name: "Eventasaurus",
        locale: "en_US",
        twitter_card: "summary_large_image",
        twitter_site: nil
      }

      html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)

      # Open Graph tags
      assert html =~ ~s(<meta property="og:type" content="event")
      assert html =~ ~s(<meta property="og:title" content="Test Event")
      assert html =~ ~s(<meta property="og:description" content="This is a test event description")
      assert html =~ ~s(<meta property="og:image" content="https://example.com/image.jpg")
      assert html =~ ~s(<meta property="og:image:width" content="1200")
      assert html =~ ~s(<meta property="og:image:height" content="630")
      assert html =~ ~s(<meta property="og:url" content="https://example.com/events/test")
      assert html =~ ~s(<meta property="og:site_name" content="Eventasaurus")
      assert html =~ ~s(<meta property="og:locale" content="en_US")

      # Twitter Card tags
      assert html =~ ~s(<meta name="twitter:card" content="summary_large_image")
      assert html =~ ~s(<meta name="twitter:title" content="Test Event")
      assert html =~ ~s(<meta name="twitter:description" content="This is a test event description")
      assert html =~ ~s(<meta name="twitter:image" content="https://example.com/image.jpg")

      # Meta description
      assert html =~ ~s(<meta name="description" content="This is a test event description")
    end

    test "uses default values when not provided" do
      assigns = %{
        title: "Test Page",
        description: "Test description",
        image_url: "https://example.com/image.jpg",
        url: "https://example.com/test"
      }

      html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)

      # Should use defaults
      assert html =~ ~s(<meta property="og:type" content="website")
      assert html =~ ~s(<meta property="og:image:width" content="1200")
      assert html =~ ~s(<meta property="og:image:height" content="630")
      assert html =~ ~s(<meta property="og:site_name" content="Eventasaurus")
      assert html =~ ~s(<meta property="og:locale" content="en_US")
      assert html =~ ~s(<meta name="twitter:card" content="summary_large_image")
    end

    test "includes Twitter site tag when provided" do
      assigns = %{
        title: "Test Event",
        description: "Test description",
        image_url: "https://example.com/image.jpg",
        url: "https://example.com/test",
        twitter_site: "@eventasaurus"
      }

      html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)

      assert html =~ ~s(<meta name="twitter:site" content="@eventasaurus")
    end

    test "does not include Twitter site tag when nil" do
      assigns = %{
        title: "Test Event",
        description: "Test description",
        image_url: "https://example.com/image.jpg",
        url: "https://example.com/test",
        twitter_site: nil
      }

      html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)

      refute html =~ ~s(twitter:site)
    end

    test "handles different Open Graph types" do
      types = ["website", "article", "event", "product"]

      for type <- types do
        assigns = %{
          type: type,
          title: "Test",
          description: "Test description",
          image_url: "https://example.com/image.jpg",
          url: "https://example.com/test"
        }

        html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)
        assert html =~ ~s(<meta property="og:type" content="#{type}")
      end
    end

    test "handles different locales" do
      locales = ["en_US", "pl_PL", "es_ES", "fr_FR"]

      for locale <- locales do
        assigns = %{
          title: "Test",
          description: "Test description",
          image_url: "https://example.com/image.jpg",
          url: "https://example.com/test",
          locale: locale
        }

        html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)
        assert html =~ ~s(<meta property="og:locale" content="#{locale}")
      end
    end

    test "handles different Twitter card types" do
      card_types = ["summary", "summary_large_image", "player"]

      for card_type <- card_types do
        assigns = %{
          title: "Test",
          description: "Test description",
          image_url: "https://example.com/image.jpg",
          url: "https://example.com/test",
          twitter_card: card_type
        }

        html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)
        assert html =~ ~s(<meta name="twitter:card" content="#{card_type}")
      end
    end

    test "handles special characters in content" do
      assigns = %{
        title: ~s(Event with "Quotes" & Ampersands),
        description: ~s(Description with <tags> and 'quotes'),
        image_url: "https://example.com/image.jpg",
        url: "https://example.com/test"
      }

      html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)

      # Phoenix should escape these properly
      assert html =~ "Event with"
      assert html =~ "Description with"
    end

    test "handles long titles and descriptions" do
      long_title = String.duplicate("A", 200)
      long_description = String.duplicate("B", 1000)

      assigns = %{
        title: long_title,
        description: long_description,
        image_url: "https://example.com/image.jpg",
        url: "https://example.com/test"
      }

      html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)

      # Should not truncate - let platforms handle it
      assert html =~ long_title
      assert html =~ long_description
    end

    test "handles custom image dimensions" do
      assigns = %{
        title: "Test",
        description: "Test description",
        image_url: "https://example.com/image.jpg",
        image_width: 800,
        image_height: 400,
        url: "https://example.com/test"
      }

      html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)

      assert html =~ ~s(<meta property="og:image:width" content="800")
      assert html =~ ~s(<meta property="og:image:height" content="400")
    end

    test "renders minimal required attributes" do
      assigns = %{
        title: "Minimal Test",
        description: "Minimal description",
        image_url: "https://example.com/image.jpg",
        url: "https://example.com/test"
      }

      # Should not raise error with just required attributes
      html = render_component(&OpenGraphComponent.open_graph_tags/1, assigns)

      assert html =~ "Minimal Test"
      assert html =~ "Minimal description"
    end
  end
end
