defmodule EventasaurusWeb.Dev.CdnTestController do
  @moduledoc """
  Development-only controller for testing Cloudflare CDN image transformations.

  This page allows visual verification of the CDN helper before integrating it
  into production templates.

  Access at: /dev/cdn-test (dev environment only)
  """
  use EventasaurusWeb, :controller

  def index(conn, _params) do
    # Sample external images for testing
    sample_images = [
      %{
        name: "Wikipedia Image",
        url:
          "https://upload.wikimedia.org/wikipedia/commons/4/43/Bonnet_macaque_%28Macaca_radiata%29_Photograph_By_Shantanu_Kuveskar.jpg",
        description: "Large wildlife photo from Wikipedia Commons"
      },
      %{
        name: "Placeholder Image",
        url: "https://placehold.co/1600x900/png",
        description: "High-resolution placeholder image"
      },
      %{
        name: "Unsplash Photo",
        url: "https://images.unsplash.com/photo-1506905925346-21bda4d32df4",
        description: "Mountain landscape from Unsplash"
      }
    ]

    # Transformation examples to test
    transformations = [
      %{
        name: "Original",
        opts: [],
        description: "No transformations applied"
      },
      %{
        name: "Thumbnail",
        opts: [width: 400, height: 300, fit: "cover", quality: 85],
        description: "400x300 thumbnail with cover fit"
      },
      %{
        name: "Desktop",
        opts: [width: 1200, quality: 90],
        description: "1200px wide for desktop displays"
      },
      %{
        name: "Mobile",
        opts: [width: 800, quality: 85, format: "webp"],
        description: "800px wide WebP for mobile"
      },
      %{
        name: "Retina Mobile",
        opts: [width: 800, dpr: 2, quality: 80],
        description: "800px with 2x DPR for retina displays"
      },
      %{
        name: "Low Quality",
        opts: [width: 600, quality: 50],
        description: "600px with reduced quality"
      }
    ]

    # Check CDN status
    cdn_enabled = Application.get_env(:eventasaurus, :cdn)[:enabled] || false
    cdn_domain = Application.get_env(:eventasaurus, :cdn)[:domain] || "cdn.wombie.com"

    render(conn, :index,
      sample_images: sample_images,
      transformations: transformations,
      cdn_enabled: cdn_enabled,
      cdn_domain: cdn_domain
    )
  end
end
