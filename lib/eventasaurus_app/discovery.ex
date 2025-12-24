defmodule EventasaurusApp.Discovery do
  @moduledoc """
  High-level discovery functions for finding people to connect with.

  This module provides composable, privacy-respecting discovery queries
  that can be used across the application. All functions respect user
  privacy preferences by default.

  ## Privacy

  All discovery functions automatically filter out users who have:
  - `discoverable_in_suggestions: false`
  - `show_on_attendee_lists: false` (for event-based discovery)

  ## Core Concepts

  - **Friends of Friends**: People known by your connections (2 degrees)
  - **Event Co-Attendees**: People who attended the same events as you
  - **Upcoming Event Attendees**: People attending events you plan to attend
  - **Shared Events**: The actual events two users both attended

  ## Usage

      # Find friends-of-friends
      Discovery.friends_of_friends(user, limit: 10)

      # Find people from shared events
      Discovery.event_co_attendees(user, timeframe: :past, limit: 20)

      # Find people at upcoming events
      Discovery.upcoming_event_attendees(user, days_ahead: 30)

      # Get shared event details between two users
      Discovery.shared_events(user1, user2, limit: 5)

  ## Extensibility

  This module is designed to be extended with additional discovery sources:
  - Group members from shared groups
  - Location-based discovery (same city)
  - Interest-based (attending similar event types)
  """

  import Ecto.Query, warn: false

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Accounts.UserPreferences
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Events.EventParticipant
  alias EventasaurusApp.Events.EventUser
  alias EventasaurusApp.Relationships
  alias EventasaurusApp.Relationships.UserRelationship

  # =============================================================================
  # Privacy Helpers
  # =============================================================================

  @doc """
  Returns a query fragment that filters to only discoverable users.

  Users are discoverable if:
  - They have no preferences set (defaults to discoverable)
  - They have `discoverable_in_suggestions: true`

  ## Examples

      iex> discoverable_user_ids()
      #Ecto.Query<...>
  """
  @spec discoverable_user_ids() :: Ecto.Query.t()
  def discoverable_user_ids do
    # Users are discoverable if:
    # 1. They have no preferences (defaults apply)
    # 2. They have preferences with discoverable_in_suggestions = true
    from(u in User,
      left_join: prefs in UserPreferences,
      on: prefs.user_id == u.id,
      where: is_nil(prefs.id) or prefs.discoverable_in_suggestions == true,
      select: u.id
    )
  end

  @doc """
  Returns a query fragment that filters to users visible on attendee lists.

  Users are visible if:
  - They have no preferences set (defaults to visible)
  - They have `show_on_attendee_lists: true`

  ## Examples

      iex> attendee_visible_user_ids()
      #Ecto.Query<...>
  """
  @spec attendee_visible_user_ids() :: Ecto.Query.t()
  def attendee_visible_user_ids do
    from(u in User,
      left_join: prefs in UserPreferences,
      on: prefs.user_id == u.id,
      where: is_nil(prefs.id) or prefs.show_on_attendee_lists == true,
      select: u.id
    )
  end

  @doc """
  Checks if a user is discoverable in suggestions.

  ## Examples

      iex> discoverable?(user)
      true
  """
  @spec discoverable?(User.t()) :: boolean()
  def discoverable?(%User{} = user) do
    prefs = Accounts.get_preferences_or_defaults(user)
    prefs.discoverable_in_suggestions
  end

  @doc """
  Checks if a user is visible on attendee lists.

  ## Examples

      iex> visible_on_attendee_lists?(user)
      true
  """
  @spec visible_on_attendee_lists?(User.t()) :: boolean()
  def visible_on_attendee_lists?(%User{} = user) do
    prefs = Accounts.get_preferences_or_defaults(user)
    prefs.show_on_attendee_lists
  end

  # =============================================================================
  # Friends of Friends Discovery
  # =============================================================================

  @doc """
  Find friends-of-friends with mutual connection details.

  Wraps `Relationships.suggested_connections/2` with privacy filtering
  and optional mutual friend name inclusion.

  ## Options

  - `:limit` - Maximum results (default: 10)
  - `:min_mutual` - Minimum mutual connections required (default: 1)
  - `:include_mutual_users` - Include list of mutual friend users (default: false)
  - `:skip_privacy_filter` - Skip privacy filtering (default: false, use with caution)

  ## Returns

      [%{
        user: %User{},
        mutual_count: 3,
        mutual_users: [%User{}, ...]  # if include_mutual_users: true
      }]

  ## Examples

      iex> friends_of_friends(user, limit: 5)
      [%{user: %User{name: "Jane"}, mutual_count: 3}]

      iex> friends_of_friends(user, include_mutual_users: true)
      [%{user: %User{}, mutual_count: 2, mutual_users: [%User{}, %User{}]}]
  """
  @spec friends_of_friends(User.t(), keyword()) :: [map()]
  def friends_of_friends(%User{} = user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    min_mutual = Keyword.get(opts, :min_mutual, 1)
    include_mutual_users = Keyword.get(opts, :include_mutual_users, false)
    skip_privacy = Keyword.get(opts, :skip_privacy_filter, false)

    # Get base suggestions from Relationships
    suggestions = Relationships.suggested_connections(user, limit: limit * 2, min_mutual: min_mutual)

    # Apply privacy filter
    filtered =
      if skip_privacy do
        suggestions
      else
        discoverable_ids = Repo.all(discoverable_user_ids()) |> MapSet.new()

        Enum.filter(suggestions, fn %{user: suggested_user} ->
          MapSet.member?(discoverable_ids, suggested_user.id)
        end)
      end

    # Optionally enhance with mutual user details
    results =
      if include_mutual_users do
        Enum.map(filtered, fn %{user: suggested_user, mutual_count: count} ->
          mutual_users = Relationships.mutual_connections(user, suggested_user)

          %{
            user: suggested_user,
            mutual_count: count,
            mutual_users: mutual_users
          }
        end)
      else
        filtered
      end

    # Apply final limit
    Enum.take(results, limit)
  end

  # =============================================================================
  # Shared Events Discovery
  # =============================================================================

  @doc """
  Get the actual events that two users both attended.

  This is useful for showing connection context like "Met at Jazz Night, Wine Tasting".
  Considers both EventParticipant (attendees) and EventUser (organizers) records.

  ## Options

  - `:limit` - Maximum events to return (default: 5)
  - `:order` - `:recent` or `:oldest` (default: :recent)
  - `:include_upcoming` - Include future events (default: false)

  ## Returns

      [%Event{}, ...]

  ## Examples

      iex> shared_events(user1, user2)
      [%Event{title: "Jazz Night"}, %Event{title: "Wine Tasting"}]

      iex> shared_events(user1, user2, limit: 1, order: :oldest)
      [%Event{title: "First Meetup"}]
  """
  @spec shared_events(User.t(), User.t(), keyword()) :: [Event.t()]
  def shared_events(%User{id: user1_id}, %User{id: user2_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    order = Keyword.get(opts, :order, :recent)
    include_upcoming = Keyword.get(opts, :include_upcoming, false)

    # Valid participation statuses
    valid_participant_statuses = [:accepted, :confirmed_with_order]
    valid_event_user_roles = ["organizer", "host", "cohost", "attendee"]

    # Get event IDs where user1 participated
    user1_participant_events =
      from(ep in EventParticipant,
        where: ep.user_id == ^user1_id,
        where: ep.status in ^valid_participant_statuses,
        where: is_nil(ep.deleted_at),
        select: ep.event_id
      )

    user1_organizer_events =
      from(eu in EventUser,
        where: eu.user_id == ^user1_id,
        where: eu.role in ^valid_event_user_roles,
        where: is_nil(eu.deleted_at),
        select: eu.event_id
      )

    user1_event_ids = Repo.all(union_all(user1_participant_events, ^user1_organizer_events))

    # Get event IDs where user2 participated
    user2_participant_events =
      from(ep in EventParticipant,
        where: ep.user_id == ^user2_id,
        where: ep.status in ^valid_participant_statuses,
        where: is_nil(ep.deleted_at),
        select: ep.event_id
      )

    user2_organizer_events =
      from(eu in EventUser,
        where: eu.user_id == ^user2_id,
        where: eu.role in ^valid_event_user_roles,
        where: is_nil(eu.deleted_at),
        select: eu.event_id
      )

    user2_event_ids = Repo.all(union_all(user2_participant_events, ^user2_organizer_events))

    # Find intersection
    shared_event_ids = MapSet.intersection(MapSet.new(user1_event_ids), MapSet.new(user2_event_ids))

    if MapSet.size(shared_event_ids) == 0 do
      []
    else
      shared_ids_list = MapSet.to_list(shared_event_ids)

      query =
        from(e in Event,
          where: e.id in ^shared_ids_list,
          where: is_nil(e.deleted_at)
        )

      # Filter by time if not including upcoming
      query =
        if include_upcoming do
          query
        else
          now = DateTime.utc_now()
          from(e in query, where: e.start_at <= ^now)
        end

      # Apply ordering
      query =
        case order do
          :recent -> from(e in query, order_by: [desc: e.start_at])
          :oldest -> from(e in query, order_by: [asc: e.start_at])
        end

      query
      |> limit(^limit)
      |> Repo.all()
    end
  end

  @doc """
  Counts the number of shared events between two users.

  More efficient than `shared_events/3` when you only need the count.

  ## Examples

      iex> shared_event_count(user1, user2)
      5
  """
  @spec shared_event_count(User.t(), User.t()) :: integer()
  def shared_event_count(%User{} = user1, %User{} = user2) do
    length(shared_events(user1, user2, limit: 1000))
  end

  # =============================================================================
  # Event Co-Attendees Discovery
  # =============================================================================

  @doc """
  Find people from events you've attended.

  Returns users who attended the same events as you, excluding
  people you're already connected with (by default).

  ## Options

  - `:limit` - Maximum results (default: 20)
  - `:timeframe` - `:past`, `:upcoming`, or `:all` (default: :past)
  - `:exclude_connected` - Filter out existing connections (default: true)
  - `:min_shared_events` - Minimum shared events required (default: 1)
  - `:skip_privacy_filter` - Skip privacy filtering (default: false)
  - `:event_id` - Limit to a specific event (optional)

  ## Returns

      [%{
        user: %User{},
        shared_events: [%Event{}, ...],
        shared_event_count: 3,
        mutual_count: 1
      }]

  ## Examples

      iex> event_co_attendees(user, limit: 10)
      [%{user: %User{}, shared_event_count: 3, shared_events: [...]}]

      iex> event_co_attendees(user, timeframe: :upcoming)
      [%{user: %User{}, shared_event_count: 1, shared_events: [...]}]
  """
  @spec event_co_attendees(User.t(), keyword()) :: [map()]
  def event_co_attendees(%User{id: user_id} = user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    timeframe = Keyword.get(opts, :timeframe, :past)
    exclude_connected = Keyword.get(opts, :exclude_connected, true)
    min_shared_events = Keyword.get(opts, :min_shared_events, 1)
    skip_privacy = Keyword.get(opts, :skip_privacy_filter, false)
    specific_event_id = Keyword.get(opts, :event_id)

    now = DateTime.utc_now()

    # Valid participation statuses
    valid_participant_statuses = [:accepted, :confirmed_with_order]
    valid_event_user_roles = ["organizer", "host", "cohost", "attendee"]

    # Get events the user attended
    user_participant_events =
      from(ep in EventParticipant,
        join: e in Event,
        on: e.id == ep.event_id,
        where: ep.user_id == ^user_id,
        where: ep.status in ^valid_participant_statuses,
        where: is_nil(ep.deleted_at),
        where: is_nil(e.deleted_at),
        select: e.id
      )

    user_organizer_events =
      from(eu in EventUser,
        join: e in Event,
        on: e.id == eu.event_id,
        where: eu.user_id == ^user_id,
        where: eu.role in ^valid_event_user_roles,
        where: is_nil(eu.deleted_at),
        where: is_nil(e.deleted_at),
        select: e.id
      )

    # Apply timeframe filter
    user_participant_events =
      case timeframe do
        :past ->
          from([ep, e] in user_participant_events, where: e.start_at <= ^now)

        :upcoming ->
          from([ep, e] in user_participant_events, where: e.start_at > ^now)

        :all ->
          user_participant_events
      end

    user_organizer_events =
      case timeframe do
        :past ->
          from([eu, e] in user_organizer_events, where: e.start_at <= ^now)

        :upcoming ->
          from([eu, e] in user_organizer_events, where: e.start_at > ^now)

        :all ->
          user_organizer_events
      end

    # Apply specific event filter if provided
    user_participant_events =
      if specific_event_id do
        from([ep, e] in user_participant_events, where: e.id == ^specific_event_id)
      else
        user_participant_events
      end

    user_organizer_events =
      if specific_event_id do
        from([eu, e] in user_organizer_events, where: e.id == ^specific_event_id)
      else
        user_organizer_events
      end

    user_event_ids =
      Repo.all(union_all(user_participant_events, ^user_organizer_events))
      |> Enum.uniq()

    if Enum.empty?(user_event_ids) do
      []
    else
      # Find other users at these events (as participants)
      co_attendee_participants =
        from(ep in EventParticipant,
          where: ep.event_id in ^user_event_ids,
          where: ep.user_id != ^user_id,
          where: ep.status in ^valid_participant_statuses,
          where: is_nil(ep.deleted_at),
          group_by: ep.user_id,
          having: count(ep.event_id) >= ^min_shared_events,
          select: %{user_id: ep.user_id, event_count: count(ep.event_id)}
        )

      # Find other users at these events (as organizers)
      co_attendee_organizers =
        from(eu in EventUser,
          where: eu.event_id in ^user_event_ids,
          where: eu.user_id != ^user_id,
          where: eu.role in ^valid_event_user_roles,
          where: is_nil(eu.deleted_at),
          group_by: eu.user_id,
          having: count(eu.event_id) >= ^min_shared_events,
          select: %{user_id: eu.user_id, event_count: count(eu.event_id)}
        )

      participant_results = Repo.all(co_attendee_participants)
      organizer_results = Repo.all(co_attendee_organizers)

      # Merge counts for users who appear in both
      user_event_counts =
        (participant_results ++ organizer_results)
        |> Enum.group_by(& &1.user_id)
        |> Enum.map(fn {uid, entries} ->
          # Take max count (they might be counted in both)
          %{user_id: uid, event_count: Enum.max_by(entries, & &1.event_count).event_count}
        end)
        |> Enum.filter(fn %{event_count: count} -> count >= min_shared_events end)

      # Get user IDs to exclude (already connected)
      exclude_ids =
        if exclude_connected do
          connected_ids =
            from(r in UserRelationship,
              where: r.user_id == ^user_id and r.status == :active,
              select: r.related_user_id
            )
            |> Repo.all()

          MapSet.new([user_id | connected_ids])
        else
          MapSet.new([user_id])
        end

      # Apply privacy filter
      discoverable_ids =
        if skip_privacy do
          nil
        else
          Repo.all(attendee_visible_user_ids()) |> MapSet.new()
        end

      # Filter and build results
      user_event_counts
      |> Enum.reject(fn %{user_id: uid} -> MapSet.member?(exclude_ids, uid) end)
      |> Enum.filter(fn %{user_id: uid} ->
        skip_privacy or MapSet.member?(discoverable_ids, uid)
      end)
      |> Enum.sort_by(fn %{event_count: count} -> count end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn %{user_id: uid, event_count: count} ->
        other_user = Repo.get!(User, uid)
        # Include upcoming events if timeframe allows
        include_upcoming = timeframe in [:upcoming, :all]
        events = shared_events(user, other_user, limit: 5, include_upcoming: include_upcoming)
        mutual = Relationships.mutual_connections(user, other_user)

        %{
          user: other_user,
          shared_events: events,
          shared_event_count: count,
          mutual_count: length(mutual)
        }
      end)
    end
  end

  # =============================================================================
  # Upcoming Event Attendees Discovery
  # =============================================================================

  @doc """
  Find people attending your upcoming events.

  Useful for pre-event networking suggestions.

  ## Options

  - `:limit` - Maximum results (default: 20)
  - `:days_ahead` - How far ahead to look in days (default: 30)
  - `:exclude_connected` - Filter out existing connections (default: true)
  - `:skip_privacy_filter` - Skip privacy filtering (default: false)

  ## Returns

      [%{
        user: %User{},
        upcoming_events: [%Event{}, ...],
        upcoming_event_count: 2,
        mutual_count: 2
      }]

  ## Examples

      iex> upcoming_event_attendees(user, days_ahead: 14)
      [%{user: %User{}, upcoming_events: [...], upcoming_event_count: 2}]
  """
  @spec upcoming_event_attendees(User.t(), keyword()) :: [map()]
  def upcoming_event_attendees(%User{} = user, opts \\ []) do
    days_ahead = Keyword.get(opts, :days_ahead, 30)
    opts = Keyword.put(opts, :timeframe, :upcoming)

    # Filter to only events within the days_ahead window
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, days_ahead * 24 * 60 * 60, :second)

    results = event_co_attendees(user, opts)

    # Further filter events to be within the window
    Enum.map(results, fn result ->
      filtered_events =
        Enum.filter(result.shared_events, fn event ->
          DateTime.compare(event.start_at, now) == :gt and
            DateTime.compare(event.start_at, cutoff) != :gt
        end)

      result
      |> Map.put(:upcoming_events, filtered_events)
      |> Map.put(:upcoming_event_count, length(filtered_events))
      |> Map.delete(:shared_events)
      |> Map.delete(:shared_event_count)
    end)
    |> Enum.filter(fn %{upcoming_event_count: count} -> count > 0 end)
  end

  # =============================================================================
  # Combined Discovery
  # =============================================================================

  @doc """
  Combined discovery with all sources.

  Returns a unified discovery feed with results from all sources,
  tagged by discovery type. Results are deduplicated (same user from
  multiple sources appears once with best context).

  ## Options

  - `:limit` - Maximum results per source (default: 10)
  - `:sources` - List of sources to include (default: all)
    - `:friends_of_friends`
    - `:event_co_attendees`
    - `:upcoming_events`

  ## Returns

      [%{
        user: %User{},
        source: :friends_of_friends | :event_co_attendees | :upcoming_events,
        context: "3 mutual friends" | "Both at Jazz Night" | "Both attending Wine Tasting",
        mutual_count: integer(),
        ...source-specific fields...
      }]

  ## Examples

      iex> discover(user, limit: 5)
      [%{user: %User{}, source: :friends_of_friends, context: "3 mutual friends"}]
  """
  @spec discover(User.t(), keyword()) :: [map()]
  def discover(%User{} = user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    sources =
      Keyword.get(opts, :sources, [:friends_of_friends, :event_co_attendees, :upcoming_events])

    results = []

    # Gather results from each source
    results =
      if :friends_of_friends in sources do
        fof_results =
          friends_of_friends(user, limit: limit)
          |> Enum.map(fn result ->
            context = format_mutual_context(result.mutual_count)

            Map.merge(result, %{
              source: :friends_of_friends,
              context: context
            })
          end)

        results ++ fof_results
      else
        results
      end

    results =
      if :event_co_attendees in sources do
        co_results =
          event_co_attendees(user, limit: limit, timeframe: :past)
          |> Enum.map(fn result ->
            context = format_event_context(result.shared_events)

            Map.merge(result, %{
              source: :event_co_attendees,
              context: context
            })
          end)

        results ++ co_results
      else
        results
      end

    results =
      if :upcoming_events in sources do
        upcoming_results =
          upcoming_event_attendees(user, limit: limit)
          |> Enum.map(fn result ->
            context = format_upcoming_context(result.upcoming_events)

            Map.merge(result, %{
              source: :upcoming_events,
              context: context
            })
          end)

        results ++ upcoming_results
      else
        results
      end

    # Deduplicate by user, keeping the entry with the best context
    # Priority: upcoming_events > event_co_attendees > friends_of_friends
    source_priority = %{upcoming_events: 1, event_co_attendees: 2, friends_of_friends: 3}

    results
    |> Enum.group_by(fn %{user: u} -> u.id end)
    |> Enum.map(fn {_user_id, entries} ->
      Enum.min_by(entries, fn entry -> Map.get(source_priority, entry.source, 99) end)
    end)
    |> Enum.sort_by(fn entry -> Map.get(source_priority, entry.source, 99) end)
    |> Enum.take(limit * length(sources))
  end

  # =============================================================================
  # Context Formatting Helpers
  # =============================================================================

  defp format_mutual_context(1), do: "1 mutual friend"
  defp format_mutual_context(count), do: "#{count} mutual friends"

  defp format_event_context([]), do: "Shared events"

  defp format_event_context([event | _rest]) do
    "Both at #{event.title}"
  end

  defp format_upcoming_context([]), do: "Attending same events"

  defp format_upcoming_context([event | _rest]) do
    "Both attending #{event.title}"
  end
end
