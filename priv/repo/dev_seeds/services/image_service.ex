defmodule DevSeeds.ImageService do
  @moduledoc """
  Centralized service for handling event image assignment.
  
  This service ensures that all events get appropriate images based on
  their type, category, and other characteristics. It provides fallbacks
  and handles the existing DefaultImagesService integration.
  """
  
  @doc """
  Gets image attributes for an event based on its type and options.
  
  ## Parameters
  - event_type: atom representing the event type (:conference, :wedding, etc.)
  - options: keyword list of options
    - image_category: override the default image category
    - force_fallback: boolean to force using fallback image
    
  ## Returns
  Map with cover_image_url and potentially other image-related attributes
  
  ## Examples
  
      # Get image for a conference event
      attrs = DevSeeds.ImageService.get_image_attributes(:conference)
      # => %{cover_image_url: "/images/events/business/conference.png"}
      
      # Override image category
      attrs = DevSeeds.ImageService.get_image_attributes(:wedding, image_category: "celebration")
  """
  def get_image_attributes(event_type, options \\ []) do
    image_category = Keyword.get(options, :image_category) || get_default_image_category(event_type)
    force_fallback = Keyword.get(options, :force_fallback, false)
    
    if force_fallback do
      get_fallback_image()
    else
      get_image_for_category(image_category) || get_fallback_image()
    end
  end
  
  @doc """
  Gets a random image from the DefaultImagesService or returns fallback.
  
  This maintains compatibility with the existing image system while
  providing guaranteed fallbacks.
  """
  def get_random_image_attributes() do
    alias EventasaurusWeb.Services.DefaultImagesService
    
    case DefaultImagesService.get_random_image() do
      nil ->
        get_fallback_image()
      
      image ->
        %{cover_image_url: image.url}
    end
  end
  
  # Private functions
  
  # Maps event types to appropriate image categories
  defp get_default_image_category(:conference), do: "business"
  defp get_default_image_category(:wedding), do: "celebration"  
  defp get_default_image_category(:workshop), do: "education"
  defp get_default_image_category(:meetup), do: "social"
  defp get_default_image_category(:party), do: "celebration"
  defp get_default_image_category(:festival), do: "entertainment"
  defp get_default_image_category(:seminar), do: "education"
  defp get_default_image_category(:retreat), do: "wellness"
  defp get_default_image_category(:networking), do: "business"
  defp get_default_image_category(:launch), do: "business"
  defp get_default_image_category(_), do: "general"
  
  # Attempts to get an image for a specific category
  # Currently uses the random image service, but could be extended
  # to support category-specific selection
  defp get_image_for_category(_category) do
    alias EventasaurusWeb.Services.DefaultImagesService
    
    case DefaultImagesService.get_random_image() do
      nil -> nil
      image -> %{cover_image_url: image.url}
    end
  end
  
  # Provides a guaranteed fallback image that should always work
  defp get_fallback_image() do
    %{cover_image_url: "/images/events/general/high-five-dino.png"}
  end
  
  @doc """
  Validates that an event has a proper image assigned.
  
  ## Parameters
  - event: event struct or map with image attributes
  
  ## Returns
  - {:ok, event} if image is valid
  - {:error, reason} if image is missing or invalid
  """
  def validate_event_image(event) do
    case Map.get(event, :cover_image_url) do
      nil ->
        {:error, "Event missing cover_image_url"}
        
      "" ->
        {:error, "Event has empty cover_image_url"}
        
      url when is_binary(url) ->
        {:ok, event}
        
      _ ->
        {:error, "Event has invalid cover_image_url type"}
    end
  end
  
  @doc """
  Fixes an event's image if it's missing or invalid.
  
  ## Parameters  
  - event: event struct or map
  - event_type: atom representing event type for appropriate image selection
  
  ## Returns
  Updated event with proper image attributes
  """
  def ensure_event_has_image(event, event_type \\ :general) do
    case validate_event_image(event) do
      {:ok, _} -> 
        event  # Image is fine, return as-is
        
      {:error, _reason} ->
        # Image is missing/invalid, add a new one
        image_attrs = get_image_attributes(event_type)
        Map.merge(event, image_attrs)
    end
  end
end