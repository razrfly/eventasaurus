defmodule EventasaurusWeb.Resolvers.PollResolver do
  require Logger
  import Ecto.Query

  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Resolvers.Helpers

  @spec event_polls(any(), %{slug: String.t()}, map()) :: {:ok, [map()]} | {:error, String.t()}
  def event_polls(_parent, %{slug: slug}, %{context: %{current_user: _user}}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:error, "Event not found"}

      event ->
        polls = Events.list_polls(event)
        {:ok, polls}
    end
  end

  @spec vote_on_poll(any(), map(), map()) :: {:ok, map()}
  def vote_on_poll(_parent, %{poll_id: poll_id, option_id: option_id} = args, %{
        context: %{current_user: user}
      }) do
    with poll when not is_nil(poll) <- Events.get_poll(poll_id),
         poll = Repo.preload(poll, :poll_options),
         option when not is_nil(option) <-
           Enum.find(poll.poll_options, &(to_string(&1.id) == to_string(option_id))),
         {:ok, vote_data} <- build_vote_data(poll.voting_system, args) do
      case Events.create_poll_vote(option, user, vote_data, poll.voting_system) do
        {:ok, _vote} ->
          {:ok, %{success: true, errors: []}}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:ok, %{success: false, errors: Helpers.format_changeset_errors(changeset)}}

        {:error, reason} when is_binary(reason) ->
          {:ok, %{success: false, errors: [%{field: "base", message: reason}]}}

        {:error, _} ->
          {:ok, %{success: false, errors: [%{field: "base", message: "Could not cast vote"}]}}
      end
    else
      nil ->
        # Determine which lookup failed based on what exists
        poll = Events.get_poll(poll_id)

        if is_nil(poll) do
          {:ok, %{success: false, errors: [%{field: "pollId", message: "Poll not found"}]}}
        else
          {:ok, %{success: false, errors: [%{field: "optionId", message: "Option not found"}]}}
        end

      {:error, reason} when is_binary(reason) ->
        {:ok, %{success: false, errors: [%{field: "base", message: reason}]}}
    end
  end

  # Phase 2: Clear votes for re-voting
  def clear_my_votes(_parent, %{poll_id: poll_id}, %{context: %{current_user: user}}) do
    case Events.get_poll(poll_id) do
      nil ->
        {:error, "Poll not found"}

      %{phase: "closed"} ->
        {:error, "Cannot clear votes on a closed poll"}

      poll ->
        {:ok, _count} = Events.clear_user_poll_votes(poll, user)
        {:ok, reload_poll(poll.id)}
    end
  end

  # Phase 3: Create poll option (user suggestion)
  def create_poll_option(_parent, %{poll_id: poll_id, title: title} = args, %{
        context: %{current_user: user}
      }) do
    case Events.get_poll(poll_id) do
      nil ->
        {:error, "Poll not found"}

      poll ->
        if poll.phase in ["list_building", "voting_with_suggestions"] do
          attrs = %{
            "poll_id" => poll.id,
            "title" => title,
            "description" => args[:description],
            "suggested_by_id" => user.id
          }

          case Events.create_poll_option(attrs) do
            {:ok, _option} ->
              {:ok, reload_poll(poll.id)}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:error, format_changeset_message(changeset)}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, "Suggestions are not allowed in this poll phase"}
        end
    end
  end

  # Phase 4: Create poll
  def create_poll(_parent, %{event_id: event_id, title: title, voting_system: voting_system} = args, %{
        context: %{current_user: user}
      }) do
    case Events.get_event(event_id) do
      nil ->
        {:error, "Event not found"}

      event ->
        if Events.user_is_organizer?(event, user) do
          attrs = %{
            "event_id" => event.id,
            "title" => title,
            "description" => args[:description],
            "voting_system" => voting_system,
            "voting_deadline" => args[:voting_deadline],
            "created_by_id" => user.id,
            "poll_type" => "custom",
            "phase" => "list_building"
          }

          case Events.create_poll(attrs) do
            {:ok, poll} ->
              {:ok, reload_poll(poll.id)}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:error, format_changeset_message(changeset)}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, "Only organizers can create polls"}
        end
    end
  end

  # Phase 4: Update poll
  def update_poll(_parent, %{poll_id: poll_id} = args, %{context: %{current_user: user}}) do
    with poll when not is_nil(poll) <- Events.get_poll(poll_id),
         poll <- Repo.preload(poll, :event),
         true <- Events.user_is_organizer?(poll.event, user) do
      attrs =
        %{}
        |> maybe_put("title", args[:title])
        |> maybe_put("description", args[:description])
        |> maybe_put("voting_deadline", args[:voting_deadline])

      case Events.update_poll(poll, attrs) do
        {:ok, _updated} ->
          {:ok, reload_poll(poll.id)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, format_changeset_message(changeset)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      nil -> {:error, "Poll not found"}
      false -> {:error, "Only organizers can update polls"}
    end
  end

  # Phase 4: Delete poll
  def delete_poll(_parent, %{poll_id: poll_id}, %{context: %{current_user: user}}) do
    with poll when not is_nil(poll) <- Events.get_poll(poll_id),
         poll <- Repo.preload(poll, :event),
         true <- Events.user_is_organizer?(poll.event, user) do
      case Events.delete_poll(poll) do
        {:ok, _} ->
          {:ok, %{success: true, errors: []}}

        {:error, _} ->
          {:ok, %{success: false, errors: [%{field: "base", message: "Could not delete poll"}]}}
      end
    else
      nil -> {:ok, %{success: false, errors: [%{field: "pollId", message: "Poll not found"}]}}
      false -> {:ok, %{success: false, errors: [%{field: "base", message: "Only organizers can delete polls"}]}}
    end
  end

  # Phase 4: Transition poll phase
  def transition_poll_phase(_parent, %{poll_id: poll_id, phase: phase}, %{
        context: %{current_user: user}
      }) do
    with poll when not is_nil(poll) <- Events.get_poll(poll_id),
         poll <- Repo.preload(poll, :event),
         true <- Events.user_is_organizer?(poll.event, user) do
      case Events.transition_poll_phase(poll, phase) do
        {:ok, _updated} ->
          {:ok, reload_poll(poll.id)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, format_changeset_message(changeset)}

        {:error, reason} when is_binary(reason) ->
          {:error, reason}
      end
    else
      nil -> {:error, "Poll not found"}
      false -> {:error, "Only organizers can transition poll phases"}
    end
  end

  # Phase 4: Delete poll option
  def delete_poll_option(_parent, %{option_id: option_id}, %{context: %{current_user: user}}) do
    case Events.get_poll_option(option_id) do
      nil ->
        {:ok, %{success: false, errors: [%{field: "optionId", message: "Option not found"}]}}

      option ->
        option = Repo.preload(option, poll: :event)

        if Events.user_is_organizer?(option.poll.event, user) do
          case Events.delete_poll_option(option) do
            {:ok, _} ->
              {:ok, %{success: true, errors: []}}

            {:error, _} ->
              {:ok, %{success: false, errors: [%{field: "base", message: "Could not delete option"}]}}
          end
        else
          {:ok, %{success: false, errors: [%{field: "base", message: "Only organizers can delete options"}]}}
        end
    end
  end

  # Phase 5: Poll voting stats
  def poll_voting_stats(_parent, %{poll_id: poll_id}, %{context: %{current_user: _user}}) do
    case Events.get_poll(poll_id) do
      nil ->
        {:error, "Poll not found"}

      poll ->
        poll = Repo.preload(poll, poll_options: :votes)
        stats = Events.get_poll_voting_stats(poll)

        # Serialize score_distribution maps to JSON strings for GraphQL
        options =
          Enum.map(stats.options, fn opt ->
            tally = opt.tally

            tally =
              if Map.has_key?(tally, :score_distribution) and is_map(tally.score_distribution) do
                case Jason.encode(tally.score_distribution) do
                  {:ok, json} -> Map.put(tally, :score_distribution, json)
                  {:error, _} -> Map.put(tally, :score_distribution, nil)
                end
              else
                tally
              end

            Map.put(opt, :tally, tally)
          end)

        {:ok, Map.put(stats, :options, options)}
    end
  end

  # MARK: - Private helpers

  defp reload_poll(poll_id) do
    case Events.get_poll(poll_id) do
      nil ->
        nil

      poll ->
        ordered_options =
          from(po in EventasaurusApp.Events.PollOption,
            where: po.poll_id == ^poll.id and po.status == "active" and is_nil(po.deleted_at),
            order_by: [asc: po.order_index, asc: po.inserted_at],
            preload: [:suggested_by, :votes]
          )

        Repo.preload(poll, [poll_options: ordered_options], force: true)
    end
  end

  defp format_changeset_message(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_vote_data("binary", %{vote_value: value}) when value in ~w(yes maybe no) do
    {:ok, %{vote_value: value, voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("binary", %{vote_value: invalid}) do
    {:error, "Invalid binary vote value: #{inspect(invalid)}. Must be yes, maybe, or no"}
  end

  defp build_vote_data("binary", _args) do
    {:ok, %{vote_value: "yes", voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("approval", _args) do
    {:ok, %{vote_value: "selected", voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("star", %{score: score}) when is_integer(score) and score >= 1 and score <= 5 do
    {:ok, %{vote_value: "star", vote_numeric: Decimal.new(score), voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("star", _args) do
    {:error, "Star voting requires a score between 1 and 5"}
  end

  defp build_vote_data("ranked", %{score: rank}) when is_integer(rank) and rank >= 1 do
    {:ok, %{vote_value: "ranked", vote_rank: rank, voted_at: DateTime.utc_now()}}
  end

  defp build_vote_data("ranked", _args) do
    {:error, "Ranked voting requires a score as a positive integer"}
  end

  defp build_vote_data(system, _args) do
    Logger.warning("Unknown voting system #{inspect(system)}")
    {:error, "Unsupported voting system"}
  end
end
