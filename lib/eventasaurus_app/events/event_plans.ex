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
    # Check if user already has a plan for this public event
    case get_user_plan_for_event(user_id, public_event_id) do
      %EventPlan{} = existing_plan ->
        # Return existing plan with :existing tag
        {:ok, {:existing, existing_plan, existing_plan.private_event}}

      nil ->
        # Create new plan
        case create_new_plan(public_event_id, user_id, attrs) do
          {:ok, {event_plan, private_event}} ->
            {:ok, {:created, event_plan, private_event}}

          {:error, {:event_plan_error, %Ecto.Changeset{} = cs}} ->
            if unique_violation?(cs, :unique_user_plan_per_public_event) do
              case get_user_plan_for_event(user_id, public_event_id) do
                %EventPlan{} = ep -> {:ok, {:existing, ep, ep.private_event}}
                _ -> {:error, {:event_plan_error, cs}}
              end
            else
              {:error, {:event_plan_error, cs}}
            end

          other ->
            other
        end
    end
  end

  defp create_new_plan(public_event_id, user_id, attrs) do
    Repo.transaction(fn ->
      # Get the public event with sources AND movies for rich data
      public_event =
        PublicEvent
        |> Repo.get!(public_event_id)
        |> Repo.preload([:sources, :movies])

      # Use occurrence_datetime if provided, otherwise fall back to public_event.starts_at
      event_datetime =
        attrs[:occurrence_datetime] || attrs["occurrence_datetime"] || public_event.starts_at

      # Check if the event is in the past
      cond do
        is_nil(event_datetime) ->
          Repo.rollback(:missing_starts_at)

        DateTime.compare(event_datetime, DateTime.utc_now()) == :lt ->
          Repo.rollback(:event_in_past)

        true ->
          :ok
      end

      # Get description from sources if available
      description = get_description_from_sources(public_event.sources)

      # Determine venue_id: use occurrence's venue if provided, else public_event's venue
      venue_id = attrs[:venue_id] || attrs["venue_id"] || public_event.venue_id

      # Get movie data if this public event is linked to a movie
      {cover_image_url, external_image_data, rich_external_data} =
        get_movie_image_data(public_event.movies, public_event.sources)

      # Build attributes for the private event
      private_event_attrs = %{
        title: attrs["title"] || attrs[:title] || "#{public_event.title} - Private Group",
        description: description,
        # Event schema uses start_at, not starts_at!
        # Use the occurrence datetime if provided, otherwise use public_event.starts_at
        start_at: event_datetime,
        ends_at: public_event.ends_at,
        timezone:
          attrs[:timezone] || attrs["timezone"] || Map.get(public_event, :timezone) || "UTC",
        # Using atom to match Ecto.Enum
        visibility: :private,
        # Use occurrence venue if provided, otherwise public_event venue
        venue_id: venue_id,
        # Copy image from movie if available, otherwise from sources
        cover_image_url: cover_image_url,
        # Image attribution (TMDB for movies)
        external_image_data: external_image_data,
        # Rich movie context for card display
        rich_external_data: rich_external_data,
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

  # Get movie image data with TMDB attribution and rich context
  # Returns {cover_image_url, external_image_data, rich_external_data}
  # Note: rich_external_data defaults to %{} (not nil) to satisfy database NOT NULL constraint
  defp get_movie_image_data(nil, sources), do: {get_image_from_sources(sources), nil, %{}}
  defp get_movie_image_data([], sources), do: {get_image_from_sources(sources), nil, %{}}

  defp get_movie_image_data([movie | _], sources) do
    # Use movie poster if available, otherwise fall back to sources
    cover_image_url = movie.poster_url || get_image_from_sources(sources)

    # Build external_image_data with TMDB attribution
    external_image_data =
      if movie.tmdb_id && movie.poster_url do
        %{
          "source" => "tmdb",
          "url" => movie.poster_url,
          "metadata" => %{
            "tmdb_id" => movie.tmdb_id,
            "movie_title" => movie.title,
            "type" => "movie_poster"
          }
        }
      end

    # Build rich_external_data with movie context for card display
    rich_external_data =
      if movie.tmdb_id do
        %{
          "type" => "movie",
          "movie_id" => movie.id,
          "tmdb_id" => movie.tmdb_id,
          "title" => movie.title,
          "original_title" => movie.original_title,
          "poster_url" => movie.poster_url,
          "backdrop_url" => movie.backdrop_url,
          "release_date" => movie.release_date && Date.to_iso8601(movie.release_date),
          "runtime" => movie.runtime
        }
      end

    {cover_image_url, external_image_data, rich_external_data}
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}, constraint_name) do
    wanted = to_string(constraint_name)

    Enum.any?(errors, fn
      {_field, {_msg, opts}} ->
        opts[:constraint] == :unique and to_string(opts[:constraint_name] || "") == wanted

      _ ->
        false
    end)
  end
end
