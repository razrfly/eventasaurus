defmodule EventasaurusWeb.Dev.ImagekitTestController do
  @moduledoc """
  Development-only controller for testing ImageKit CDN image transformations.

  This page allows visual verification of the ImageKit helper before integrating it
  into production templates.

  Access at: /dev/imagekit-test (dev environment only)

  To test locally: IMAGEKIT_CDN_ENABLED=true mix phx.server
  """
  use EventasaurusWeb, :controller

  def index(conn, _params) do
    # Sample external images for testing (similar to venue provider images)
    sample_images = [
      %{
        name: "Google Places Style Image",
        url:
          "https://lh3.googleusercontent.com/places/ANXAkqGKvHn6b8KxZ7kxkM0kxD9pD9fD9fD9fD9fD9fD9fD9fD9fD9fD9fD9fD9f",
        description: "Simulates Google Places photo URL"
      },
      %{
        name: "Foursquare Style Image",
        url: "https://fastly.4sqi.net/img/general/600x600/12345678_abcdefg.jpg",
        description: "Simulates Foursquare venue photo URL"
      },
      %{
        name: "Unsplash Photo",
        url: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4",
        description: "Mountain landscape from Unsplash"
      }
    ]

    # Transformation examples to test (ImageKit transformation options)
    transformations = [
      %{
        name: "Original",
        opts: [],
        description: "No transformations applied"
      },
      %{
        name: "Thumbnail",
        opts: [width: 400, height: 300, crop: "maintain_ratio", quality: 85],
        description: "400x300 thumbnail with maintain ratio crop"
      },
      %{
        name: "Desktop",
        opts: [width: 1200, quality: 90],
        description: "1200px wide for desktop displays"
      },
      %{
        name: "Mobile WebP",
        opts: [width: 800, quality: 85, format: "webp"],
        description: "800px wide WebP for mobile"
      },
      %{
        name: "Auto Format",
        opts: [width: 1000, format: "auto", quality: 85],
        description: "Auto-detect best format"
      },
      %{
        name: "Low Quality",
        opts: [width: 600, quality: 50],
        description: "600px with reduced quality"
      }
    ]

    # Check ImageKit CDN status
    imagekit_config = Application.get_env(:eventasaurus, :imagekit, [])
    imagekit_enabled = Keyword.get(imagekit_config, :enabled, false)
    imagekit_id = Keyword.get(imagekit_config, :id, "wombie")
    imagekit_endpoint = Keyword.get(imagekit_config, :endpoint, "https://ik.imagekit.io/wombie")

    render(conn, :index,
      sample_images: sample_images,
      transformations: transformations,
      imagekit_enabled: imagekit_enabled,
      imagekit_id: imagekit_id,
      imagekit_endpoint: imagekit_endpoint
    )
  end
end
