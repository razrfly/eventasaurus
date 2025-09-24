defmodule EventasaurusApp.Events.EventPlans do
  @moduledoc """
  The EventPlans context for bridging public events with private friend groups.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventPlan
  alias EventasaurusApp.Accounts.User
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  @doc """
  Creates a private event plan from a public event.

  This creates a private event copying data from the public event,
  then links them via the event_plans table.
  """
  def create_from_public_event(public_event_id, user_id, attrs \\ %{}) do
    Repo.transaction(fn ->
      # Get the public event with sources
      public_event =
        PublicEvent
        |> Repo.get!(public_event_id)
        |> Repo.preload(:sources)

      # Check if the event is in the past
      cond do
        is_nil(public_event.starts_at) ->
          Repo.rollback(:missing_starts_at)

        DateTime.compare(public_event.starts_at, DateTime.utc_now()) == :lt ->
          Repo.rollback(:event_in_past)

        true ->
          :ok
      end

      # Get description from sources if available
      description = get_description_from_sources(public_event.sources)

      # Build attributes for the private event
      private_event_attrs = %{
        title: attrs["title"] || attrs[:title] || "#{public_event.title} - Private Group",
        description: description,
        # Event schema uses start_at, not starts_at!
        start_at: public_event.starts_at,
        ends_at: public_event.ends_at,
        timezone: attrs[:timezone] || attrs["timezone"] || Map.get(public_event, :timezone) || "UTC",
        # Using atom to match Ecto.Enum
        visibility: :private,
        venue_id: public_event.venue_id,
        # Copy the public event's image if available
        cover_image_url: get_image_from_sources(public_event.sources),
        # Mark this as confirmed since it's based on an existing public event
        # Using atom to match Ecto.Enum
        status: :confirmed
      }

      # Create the private event
      case Events.create_event(private_event_attrs) do
        {:ok, private_event} ->
          # Add the creator as an organizer
          case Repo.get(User, user_id) do
            nil ->
              Repo.rollback(:user_not_found)
            %User{} = user ->
              case Events.add_user_to_event(private_event, user, "organizer") do
                {:ok, _membership} -> :ok
                {:error, reason} -> Repo.rollback({:organizer_assignment_error, reason})
              end
          end

          # Create the event_plan link
          event_plan_attrs = %{
            public_event_id: public_event.id,
            private_event_id: private_event.id,
            created_by: user_id
          }

          case create_event_plan(event_plan_attrs) do
            {:ok, event_plan} ->
              {event_plan, private_event}

            {:error, changeset} ->
              Repo.rollback({:event_plan_error, changeset})
          end

        {:error, changeset} ->
          Repo.rollback({:private_event_error, changeset})
      end
    end)
  end

  @doc """
  Creates an event_plan record linking a public event to a private event.
  """
  def create_event_plan(attrs) do
    %EventPlan{}
    |> EventPlan.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets the user's plan for a specific public event if it exists.
  """
  def get_user_plan_for_event(user_id, public_event_id) do
    from(ep in EventPlan,
      where: ep.created_by == ^user_id and ep.public_event_id == ^public_event_id,
      preload: [:private_event]
    )
    |> Repo.one()
  end

  @doc """
  Checks if a user already has a plan for a public event.
  """
  def user_has_plan?(user_id, public_event_id) do
    from(ep in EventPlan,
      where: ep.created_by == ^user_id and ep.public_event_id == ^public_event_id
    )
    |> Repo.exists?()
  end

  # Private helpers

  defp get_description_from_sources(nil), do: ""
  defp get_description_from_sources([]), do: ""

  defp get_description_from_sources(sources) do
    # Try to get description in English first, then any language
    Enum.find_value(sources, "", fn source ->
      case source.description_translations do
        %{"en" => desc} when is_binary(desc) and desc != "" ->
          desc

        %{"pl" => desc} when is_binary(desc) and desc != "" ->
          desc

        translations when is_map(translations) ->
          translations
          |> Map.values()
          |> Enum.find("", &(is_binary(&1) and &1 != ""))

        _ ->
          nil
      end
    end)
  end

  defp get_image_from_sources(nil), do: nil
  defp get_image_from_sources([]), do: nil

  defp get_image_from_sources(sources) do
    Enum.find_value(sources, nil, fn source ->
      source.image_url
    end)
  end
end
