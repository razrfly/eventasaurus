defmodule EventasaurusWeb.Services.ImageManifest do
  @moduledoc """
  Manages a manifest of default event images using Phoenix's static path helpers.
  This ensures proper integration with the asset pipeline and cache-busting in production.
  """

  use EventasaurusWeb, :verified_routes

  @doc """
  Returns the complete manifest of available default images organized by category.
  Each image entry includes properly generated URLs using Phoenix's static path helpers.
  """
  def get_manifest do
    %{
      "abstract" => [
        %{
          filename: "u6742974658_Create_abstract_event_related_images_--ar_11_--v__d0605fa7-5a9c-49dd-8bbb-66c9e75a545b_0.png",
          title: "Abstract Event Image 1",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_images_--ar_11_--v__d0605fa7-5a9c-49dd-8bbb-66c9e75a545b_0.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_images_--ar_11_--v__d0605fa7-5a9c-49dd-8bbb-66c9e75a545b_1.png",
          title: "Abstract Event Image 2",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_images_--ar_11_--v__d0605fa7-5a9c-49dd-8bbb-66c9e75a545b_1.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_images_--ar_11_--v__d0605fa7-5a9c-49dd-8bbb-66c9e75a545b_2.png",
          title: "Abstract Event Image 3",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_images_--ar_11_--v__d0605fa7-5a9c-49dd-8bbb-66c9e75a545b_2.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_images_--ar_11_--v__d0605fa7-5a9c-49dd-8bbb-66c9e75a545b_3.png",
          title: "Abstract Event Image 4",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_images_--ar_11_--v__d0605fa7-5a9c-49dd-8bbb-66c9e75a545b_3.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__2df543fa-9681-4491-8c97-96530e8c3190_0.png",
          title: "Abstract Square Image 1",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__2df543fa-9681-4491-8c97-96530e8c3190_0.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__2df543fa-9681-4491-8c97-96530e8c3190_2.png",
          title: "Abstract Square Image 2",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__2df543fa-9681-4491-8c97-96530e8c3190_2.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__2df543fa-9681-4491-8c97-96530e8c3190_3.png",
          title: "Abstract Square Image 3",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__2df543fa-9681-4491-8c97-96530e8c3190_3.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__2fe9d51e-2536-49c1-8afa-45501fe5c887_0.png",
          title: "Abstract Square Image 4",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__2fe9d51e-2536-49c1-8afa-45501fe5c887_0.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__2fe9d51e-2536-49c1-8afa-45501fe5c887_1.png",
          title: "Abstract Square Image 5",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__2fe9d51e-2536-49c1-8afa-45501fe5c887_1.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__2fe9d51e-2536-49c1-8afa-45501fe5c887_3.png",
          title: "Abstract Square Image 6",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__2fe9d51e-2536-49c1-8afa-45501fe5c887_3.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__ca33e951-92b1-45be-9407-4127801faa1b_0.png",
          title: "Abstract Square Image 7",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__ca33e951-92b1-45be-9407-4127801faa1b_0.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__ca33e951-92b1-45be-9407-4127801faa1b_1.png",
          title: "Abstract Square Image 8",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__ca33e951-92b1-45be-9407-4127801faa1b_1.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__ca33e951-92b1-45be-9407-4127801faa1b_2.png",
          title: "Abstract Square Image 9",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__ca33e951-92b1-45be-9407-4127801faa1b_2.png",
          category: "abstract"
        },
        %{
          filename: "u6742974658_Create_abstract_event_related_square_images_--ar__ca33e951-92b1-45be-9407-4127801faa1b_3.png",
          title: "Abstract Square Image 10",
          url: ~p"/images/events/abstract/u6742974658_Create_abstract_event_related_square_images_--ar__ca33e951-92b1-45be-9407-4127801faa1b_3.png",
          category: "abstract"
        }
      ],
      "general" => [
        %{
          filename: "ChatGPT Image Jun 17, 2025, 02_58_52 PM.png",
          title: "ChatGPT Generated Image 1",
          url: ~p"/images/events/general/ChatGPT Image Jun 17, 2025, 02_58_52 PM.png",
          category: "general"
        },
        %{
          filename: "ChatGPT Image Jun 19, 2025, 10_58_52 AM.png",
          title: "ChatGPT Generated Image 2",
          url: ~p"/images/events/general/ChatGPT Image Jun 19, 2025, 10_58_52 AM.png",
          category: "general"
        },
        %{
          filename: "high-five-dino.png",
          title: "High Five Dino",
          url: ~p"/images/events/general/high-five-dino.png",
          category: "general"
        },
        %{
          filename: "invitation-dino.png",
          title: "Invitation Dino",
          url: ~p"/images/events/general/invitation-dino.png",
          category: "general"
        },
        %{
          filename: "metaverse.png",
          title: "Metaverse",
          url: ~p"/images/events/general/metaverse.png",
          category: "general"
        },
        %{
          filename: "surfing.png",
          title: "Surfing",
          url: ~p"/images/events/general/surfing.png",
          category: "general"
        },
        %{
          filename: "virtual-vs-inperson.png",
          title: "Virtual Vs In Person",
          url: ~p"/images/events/general/virtual-vs-inperson.png",
          category: "general"
        },
        %{
          filename: "yoga-dino.png",
          title: "Yoga Dino",
          url: ~p"/images/events/general/yoga-dino.png",
          category: "general"
        }
      ],
      "invites" => [
        %{
          filename: "u6742974658_Create_abstract_invitation_related_images_--ar_11_8245426d-b560-401c-85ce-1764615b2e23_0.png",
          title: "Invitation Abstract 1",
          url: ~p"/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_8245426d-b560-401c-85ce-1764615b2e23_0.png",
          category: "invites"
        },
        %{
          filename: "u6742974658_Create_abstract_invitation_related_images_--ar_11_8245426d-b560-401c-85ce-1764615b2e23_1.png",
          title: "Invitation Abstract 2",
          url: ~p"/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_8245426d-b560-401c-85ce-1764615b2e23_1.png",
          category: "invites"
        },
        %{
          filename: "u6742974658_Create_abstract_invitation_related_images_--ar_11_8245426d-b560-401c-85ce-1764615b2e23_2.png",
          title: "Invitation Abstract 3",
          url: ~p"/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_8245426d-b560-401c-85ce-1764615b2e23_2.png",
          category: "invites"
        },
        %{
          filename: "u6742974658_Create_abstract_invitation_related_images_--ar_11_8245426d-b560-401c-85ce-1764615b2e23_3.png",
          title: "Invitation Abstract 4",
          url: ~p"/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_8245426d-b560-401c-85ce-1764615b2e23_3.png",
          category: "invites"
        },
        %{
          filename: "u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_0.png",
          title: "Invitation Abstract 5",
          url: ~p"/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_0.png",
          category: "invites"
        },
        %{
          filename: "u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_1.png",
          title: "Invitation Abstract 6",
          url: ~p"/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_1.png",
          category: "invites"
        },
        %{
          filename: "u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_2.png",
          title: "Invitation Abstract 7",
          url: ~p"/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_2.png",
          category: "invites"
        },
        %{
          filename: "u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_3.png",
          title: "Invitation Abstract 8",
          url: ~p"/images/events/invites/u6742974658_Create_abstract_invitation_related_images_--ar_11_9838e417-fe6a-4f2e-bcab-8537775ca423_3.png",
          category: "invites"
        }
      ],
      "tech" => [
        %{
          filename: "u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_21c17afc-9dbd-4461-b34e-ec47be85fe7f_0.png",
          title: "Tech Abstract 1",
          url: ~p"/images/events/tech/u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_21c17afc-9dbd-4461-b34e-ec47be85fe7f_0.png",
          category: "tech"
        },
        %{
          filename: "u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_21c17afc-9dbd-4461-b34e-ec47be85fe7f_1.png",
          title: "Tech Abstract 2",
          url: ~p"/images/events/tech/u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_21c17afc-9dbd-4461-b34e-ec47be85fe7f_1.png",
          category: "tech"
        },
        %{
          filename: "u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_21c17afc-9dbd-4461-b34e-ec47be85fe7f_2.png",
          title: "Tech Abstract 3",
          url: ~p"/images/events/tech/u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_21c17afc-9dbd-4461-b34e-ec47be85fe7f_2.png",
          category: "tech"
        },
        %{
          filename: "u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_21c17afc-9dbd-4461-b34e-ec47be85fe7f_3.png",
          title: "Tech Abstract 4",
          url: ~p"/images/events/tech/u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_21c17afc-9dbd-4461-b34e-ec47be85fe7f_3.png",
          category: "tech"
        },
        %{
          filename: "u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_3eee4de5-41fe-4f8f-89d2-55badc43a15e_0.png",
          title: "Tech Abstract 5",
          url: ~p"/images/events/tech/u6742974658_Create_abstract_tech_related_images_--ar_11_--v_6_3eee4de5-41fe-4f8f-89d2-55badc43a15e_0.png",
          category: "tech"
        }
      ]
    }
  end

  @doc """
  Get all available categories with display names
  """
  def get_categories do
    get_manifest()
    |> Map.keys()
    |> Enum.map(fn name ->
      %{
        name: name,
        display_name: humanize_category(name),
        path: name
      }
    end)
    |> Enum.sort_by(& &1.display_name)
  end

  @doc """
  Get images for a specific category
  """
  def get_images_for_category(category) when is_binary(category) do
    get_manifest()
    |> Map.get(category, [])
  end

  def get_images_for_category(_), do: []

  @doc """
  Get a random image from all categories
  """
  def get_random_image do
    all_images = 
      get_manifest()
      |> Map.values()
      |> List.flatten()

    case all_images do
      [] -> nil
      images -> Enum.random(images)
    end
  end

  defp humanize_category(category) do
    category
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end