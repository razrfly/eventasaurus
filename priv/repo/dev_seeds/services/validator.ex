defmodule DevSeeds.Validator do
  @moduledoc """
  Validation service for seed generation.
  
  This module provides functions to validate that seeded events
  have all required attributes and are properly configured.
  """
  
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.{Event, Poll, EventParticipant}
  alias DevSeeds.{ImageService, VenueService, Helpers}
  
  @doc """
  Validates all events in the database and reports issues.
  
  ## Returns
  - {:ok, stats} if validation passes
  - {:error, issues} if validation finds problems
  
  Stats include:
  - total_events: number of events checked
  - events_with_issues: number of events with problems
  - issues: list of issue descriptions
  """
  def validate_all_events() do
    events = Repo.all(from e in Event, where: is_nil(e.deleted_at))
    
    {valid_events, issues} = 
      events
      |> Enum.map(&validate_event/1)
      |> Enum.reduce({[], []}, fn
        {:ok, event}, {valid, issues} -> {[event | valid], issues}
        {:error, event_issues}, {valid, issues} -> {valid, issues ++ event_issues}
      end)
    
    stats = %{
      total_events: length(events),
      valid_events: length(valid_events),
      events_with_issues: length(events) - length(valid_events),
      issues: issues
    }
    
    if length(issues) == 0 do
      {:ok, stats}
    else
      {:error, stats}
    end
  end
  
  @doc """
  Validates a single event for all required attributes.
  
  ## Parameters
  - event: Event struct to validate
  
  ## Returns
  - {:ok, event} if event is valid
  - {:error, [issues]} if event has problems
  """
  def validate_event(event) do
    checks = [
      check_has_required_fields(event),
      check_image_validity(event),
      check_venue_consistency(event),
      check_datetime_validity(event),
      check_status_validity(event)
    ]
    
    issues = Enum.filter(checks, fn {result, _} -> result == :error end)
             |> Enum.map(fn {_, issue} -> "Event #{event.id} (#{event.title}): #{issue}" end)
    
    if length(issues) == 0 do
      {:ok, event}
    else
      {:error, issues}
    end
  end
  
  @doc """
  Runs validation and prints a report to console.
  
  This is useful for manual testing and debugging.
  """
  def run_validation_report() do
    Helpers.section("Seed Validation Report")
    
    case validate_all_events() do
      {:ok, stats} ->
        Helpers.success("✅ All #{stats.total_events} events passed validation!")
        
      {:error, stats} ->
        Helpers.error("❌ Found issues with #{stats.events_with_issues}/#{stats.total_events} events:")
        Enum.each(stats.issues, fn issue ->
          Helpers.log("  - #{issue}", :red)
        end)
        
        # Suggest fixes
        Helpers.log("\nSuggested fixes:", :yellow)
        suggest_fixes(stats.issues)
    end
  end
  
  @doc """
  Attempts to automatically fix common issues with events.
  
  ## Parameters
  - fix_types: list of issue types to fix (:images, :venues, :all)
  
  ## Returns
  - {:ok, fixes_applied} if fixes were successful
  - {:error, reason} if fixes failed
  """
  def auto_fix_issues(fix_types \\ [:images, :venues]) do
    events = Repo.all(from e in Event, where: is_nil(e.deleted_at))
    
    fixes_applied = 
      events
      |> Enum.flat_map(fn event ->
        apply_fixes_to_event(event, fix_types)
      end)
    
    if length(fixes_applied) > 0 do
      Helpers.success("Applied #{length(fixes_applied)} fixes:")
      Enum.each(fixes_applied, fn fix ->
        Helpers.log("  ✓ #{fix}")
      end)
    end
    
    {:ok, fixes_applied}
  end
  
  # Private validation functions
  
  defp check_has_required_fields(event) do
    required_fields = [:title, :description, :start_at, :status]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      value = Map.get(event, field)
      is_nil(value) or (is_binary(value) and String.trim(value) == "")
    end)
    
    if length(missing_fields) == 0 do
      {:ok, "Required fields present"}
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end
  
  defp check_image_validity(event) do
    case ImageService.validate_event_image(event) do
      {:ok, _} -> {:ok, "Image valid"}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp check_venue_consistency(event) do
    case VenueService.validate_event_venue(event) do
      {:ok, _} -> {:ok, "Venue valid"}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp check_datetime_validity(event) do
    cond do
      is_nil(event.start_at) ->
        {:error, "Missing start_at"}
        
      event.ends_at && DateTime.compare(event.start_at, event.ends_at) == :gt ->
        {:error, "Event ends before it starts"}
        
      DateTime.compare(event.start_at, DateTime.utc_now()) == :lt ->
        # Past events are okay for seed data
        {:ok, "Past event (seed data)"}
        
      true ->
        {:ok, "Valid datetime"}
    end
  end
  
  defp check_status_validity(event) do
    valid_statuses = ["draft", "polling", "threshold", "confirmed", "canceled"]
    
    if Enum.member?(valid_statuses, event.status) do
      {:ok, "Valid status"}
    else
      {:error, "Invalid status: #{event.status}. Valid: #{Enum.join(valid_statuses, ", ")}"}
    end
  end
  
  # Auto-fix functions
  
  defp apply_fixes_to_event(event, fix_types) do
    fixes = []
    
    fixes = if :images in fix_types do
      case ImageService.validate_event_image(event) do
        {:ok, _} -> fixes
        {:error, _} -> [fix_event_image(event) | fixes]
      end
    else
      fixes
    end
    
    fixes = if :venues in fix_types do
      case VenueService.validate_event_venue(event) do
        {:ok, _} -> fixes
        {:error, _} -> [fix_event_venue(event) | fixes]
      end
    else
      fixes
    end
    
    # Filter out nil fixes
    Enum.reject(fixes, &is_nil/1)
  end
  
  defp fix_event_image(event) do
    # Determine event type for appropriate image
    event_type = guess_event_type_from_title(event.title)
    image_attrs = ImageService.get_image_attributes(event_type)
    
    changeset = Ecto.Changeset.change(event, image_attrs)
    
    case Repo.update(changeset) do
      {:ok, _updated_event} ->
        "Fixed image for event #{event.id} (#{event.title})"
      {:error, _} ->
        nil
    end
  end
  
  defp fix_event_venue(event) do
    # If event is missing venue but not marked as virtual, try to add venue
    if is_nil(event.venue_id) and not event.is_virtual do
      event_type = guess_event_type_from_title(event.title)
      
      # For simplicity, mark as virtual rather than creating venues
      changeset = Ecto.Changeset.change(event, %{
        is_virtual: true,
        virtual_venue_url: "https://meet.google.com/virtual-event"
      })
      
      case Repo.update(changeset) do
        {:ok, _updated_event} ->
          "Converted event #{event.id} to virtual (#{event.title})"
        {:error, _} ->
          nil
      end
    else
      nil
    end
  end
  
  # Helper to guess event type from title for fixes
  defp guess_event_type_from_title(title) do
    title_lower = String.downcase(title)
    
    cond do
      String.contains?(title_lower, ["conference", "tech", "summit"]) -> :conference
      String.contains?(title_lower, ["wedding", "bride", "groom"]) -> :wedding
      String.contains?(title_lower, ["workshop", "training", "class"]) -> :workshop
      String.contains?(title_lower, ["meetup", "gathering", "social"]) -> :meetup
      String.contains?(title_lower, ["party", "celebration", "birthday"]) -> :party
      String.contains?(title_lower, ["festival", "arts", "music"]) -> :festival
      String.contains?(title_lower, ["seminar", "presentation", "talk"]) -> :seminar
      String.contains?(title_lower, ["retreat", "wellness", "spa"]) -> :retreat
      String.contains?(title_lower, ["network", "business", "corporate"]) -> :networking
      String.contains?(title_lower, ["launch", "startup", "product"]) -> :launch
      true -> :general
    end
  end
  
  # Suggestion functions
  
  defp suggest_fixes(issues) do
    if Enum.any?(issues, &String.contains?(&1, "missing cover_image_url")) do
      Helpers.log("  • Run DevSeeds.Validator.auto_fix_issues([:images]) to fix missing images")
    end
    
    if Enum.any?(issues, &String.contains?(&1, "venue")) do
      Helpers.log("  • Run DevSeeds.Validator.auto_fix_issues([:venues]) to fix venue issues")
    end
    
    if Enum.any?(issues, &String.contains?(&1, "status")) do
      Helpers.log("  • Check event status values against valid enum values")
    end
  end
  
  @doc """
  Quick validation check - returns true if all events pass validation.
  """
  def all_events_valid?() do
    case validate_all_events() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
end