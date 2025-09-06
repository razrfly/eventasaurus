defmodule DevSeeds.EventTypes do
  @moduledoc """
  Configuration module for different event types.
  
  This module defines the characteristics, defaults, and requirements
  for different types of events used in seed generation.
  """
  
  @doc """
  Gets the configuration for a specific event type.
  
  ## Parameters
  - event_type: atom representing the event type
  
  ## Returns
  Map containing configuration for the event type including:
  - default_attrs: default attributes for events of this type
  - requires_venue: whether physical venue is typically required
  - image_category: default image category
  - typical_capacity: typical capacity range
  - default_status: default event status
  - description_templates: templates for generating descriptions
  
  ## Examples
  
      config = DevSeeds.EventTypes.get_configuration(:conference)
      # => %{
      #   default_attrs: %{status: :confirmed, category: "business"},
      #   requires_venue: true,
      #   image_category: "business",
      #   typical_capacity: 200,
      #   ...
      # }
  """
  def get_configuration(event_type) do
    Map.get(configurations(), event_type, get_configuration(:general))
  end
  
  @doc """
  Gets all available event type configurations.
  
  ## Returns
  Map with event type atoms as keys and configuration maps as values
  """
  def all_configurations() do
    configurations()
  end
  
  @doc """
  Gets list of all available event types.
  
  ## Returns
  List of event type atoms
  """
  def available_types() do
    Map.keys(configurations())
  end
  
  @doc """
  Checks if an event type is defined.
  
  ## Parameters
  - event_type: atom to check
  
  ## Returns
  Boolean indicating if event type is defined
  """
  def valid_type?(event_type) do
    Map.has_key?(configurations(), event_type)
  end
  
  # Private function containing all event type configurations
  defp configurations() do
    %{
      # Business Events
      conference: %{
        default_attrs: %{
          status: :confirmed,
          category: "business",
          visibility: "public",
          is_ticketed: true,
          taxation_type: "business"
        },
        requires_venue: true,
        image_category: "business",
        typical_capacity: 200,
        description_templates: [
          "Join industry leaders for this comprehensive conference on cutting-edge topics.",
          "Network with professionals and learn from expert speakers.",
          "Discover the latest trends and innovations in the industry."
        ]
      },
      
      networking: %{
        default_attrs: %{
          status: :confirmed,
          category: "business", 
          visibility: "public",
          is_ticketed: true,
          taxation_type: "business"
        },
        requires_venue: true,
        image_category: "business",
        typical_capacity: 80,
        description_templates: [
          "Connect with like-minded professionals in a relaxed atmosphere.",
          "Expand your network and discover new business opportunities.",
          "Meet industry peers and share experiences over refreshments."
        ]
      },
      
      launch: %{
        default_attrs: %{
          status: :polling,
          category: "business",
          visibility: "public", 
          is_ticketed: true,
          taxation_type: "business"
        },
        requires_venue: true,
        image_category: "business",
        typical_capacity: 120,
        description_templates: [
          "Be among the first to experience our latest product launch.",
          "Join us for an exclusive preview of exciting new innovations.",
          "Celebrate with us as we unveil our next breakthrough."
        ]
      },
      
      # Educational Events  
      workshop: %{
        default_attrs: %{
          status: :confirmed,
          category: "education",
          visibility: "public",
          is_ticketed: true,
          taxation_type: "education"
        },
        requires_venue: true,
        image_category: "education", 
        typical_capacity: 30,
        description_templates: [
          "Hands-on workshop to develop practical skills and knowledge.",
          "Interactive learning experience with expert instructors.",
          "Master new techniques through guided practice and exercises."
        ]
      },
      
      seminar: %{
        default_attrs: %{
          status: :confirmed,
          category: "education",
          visibility: "public",
          is_ticketed: true,
          taxation_type: "education"
        },
        requires_venue: true,
        image_category: "education",
        typical_capacity: 75,
        description_templates: [
          "Educational seminar featuring renowned experts and thought leaders.",
          "Deep dive into specialized topics with comprehensive coverage.",
          "Gain insights and knowledge from industry professionals."
        ]
      },
      
      # Social Events
      wedding: %{
        default_attrs: %{
          status: :polling,
          category: "personal",
          visibility: "private",
          is_ticketed: false,
          taxation_type: "personal"
        },
        requires_venue: true,
        image_category: "celebration",
        typical_capacity: 150,
        description_templates: [
          "Celebrate this special day with family and friends.",
          "Join us for a beautiful wedding ceremony and reception.",
          "Share in the joy and love of this memorable occasion."
        ]
      },
      
      party: %{
        default_attrs: %{
          status: :confirmed,
          category: "social",
          visibility: "private",
          is_ticketed: false,
          taxation_type: "personal"
        },
        requires_venue: true,
        image_category: "celebration",
        typical_capacity: 100,
        description_templates: [
          "Join us for an unforgettable celebration with friends.",
          "Party the night away with great music, food, and company.",
          "Come celebrate this special occasion with us."
        ]
      },
      
      meetup: %{
        default_attrs: %{
          status: :confirmed,
          category: "social",
          visibility: "public",
          is_ticketed: false,
          taxation_type: "personal"
        },
        requires_venue: true,
        image_category: "social",
        typical_capacity: 50,
        description_templates: [
          "Casual meetup for interesting conversations and connections.",
          "Come hang out with fellow enthusiasts and share experiences.",
          "Relaxed gathering to meet new people and have fun."
        ]
      },
      
      # Entertainment Events
      festival: %{
        default_attrs: %{
          status: :confirmed,
          category: "entertainment",
          visibility: "public",
          is_ticketed: true,
          taxation_type: "entertainment"
        },
        requires_venue: true,
        image_category: "entertainment",
        typical_capacity: 500,
        description_templates: [
          "Multi-day festival featuring amazing performances and activities.",
          "Immerse yourself in art, music, and cultural experiences.",
          "Celebrate community and creativity at this vibrant festival."
        ]
      },
      
      # Wellness Events
      retreat: %{
        default_attrs: %{
          status: :polling,
          category: "wellness",
          visibility: "public",
          is_ticketed: true,
          taxation_type: "wellness"
        },
        requires_venue: true,
        image_category: "wellness", 
        typical_capacity: 40,
        description_templates: [
          "Rejuvenating retreat to reconnect with yourself and nature.",
          "Escape the daily grind and focus on personal well-being.",
          "Transform your mind and body in a peaceful setting."
        ]
      },
      
      # Virtual Events
      webinar: %{
        default_attrs: %{
          status: :confirmed,
          category: "education",
          visibility: "public",
          is_ticketed: true,
          taxation_type: "education",
          is_virtual: true
        },
        requires_venue: false,
        image_category: "education",
        typical_capacity: 500,
        description_templates: [
          "Interactive online presentation with expert speakers.",
          "Learn from anywhere with this comprehensive webinar.",
          "Join remotely for valuable insights and Q&A sessions."
        ]
      },
      
      online_course: %{
        default_attrs: %{
          status: :confirmed,
          category: "education", 
          visibility: "public",
          is_ticketed: true,
          taxation_type: "education",
          is_virtual: true
        },
        requires_venue: false,
        image_category: "education",
        typical_capacity: 200,
        description_templates: [
          "Comprehensive online course with structured learning modules.",
          "Master new skills through self-paced online instruction.",
          "Interactive digital learning experience with expert guidance."
        ]
      },
      
      # Default/General type for fallback
      general: %{
        default_attrs: %{
          status: :draft,
          category: "general",
          visibility: "public",
          is_ticketed: false,
          taxation_type: "general"
        },
        requires_venue: true,
        image_category: "general",
        typical_capacity: 100,
        description_templates: [
          "Join us for this exciting event.",
          "Be part of something special.",
          "Don't miss this unique opportunity."
        ]
      }
    }
  end
  
  @doc """
  Generates a description for an event based on its type.
  
  ## Parameters  
  - event_type: atom representing the event type
  - custom_context: optional string to customize the description
  
  ## Returns
  String description appropriate for the event type
  """
  def generate_description(event_type, custom_context \\ nil) do
    config = get_configuration(event_type)
    templates = config.description_templates
    
    base_description = Enum.random(templates)
    
    if custom_context do
      base_description <> " " <> custom_context
    else
      base_description
    end
  end
  
  @doc """
  Gets appropriate timezone for an event type.
  
  ## Parameters
  - event_type: atom representing the event type
  - location: optional location hint
  
  ## Returns
  String timezone identifier
  """
  def get_timezone(event_type, location \\ nil) do
    # This could be more sophisticated based on venue location
    # For now, default to common US timezones based on event type
    
    case {event_type, location} do
      {:webinar, _} -> "UTC" # Virtual events often use UTC
      {:online_course, _} -> "UTC"
      {_, "San Francisco"} -> "America/Los_Angeles"
      {_, "Los Angeles"} -> "America/Los_Angeles" 
      {_, "San Diego"} -> "America/Los_Angeles"
      {_, _} -> "America/Los_Angeles" # Default to Pacific for seed data
    end
  end
end