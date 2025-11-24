defmodule EventasaurusApp.Planning.OccurrencePlannings do
  @moduledoc """
  The OccurrencePlannings context for managing poll-based occurrence selection workflows.

  This context handles the flexible "Plan with friends" feature where users poll
  friends to decide on a specific occurrence (movie showtime, restaurant slot, etc.)
  before finalizing to an event_plan.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Planning.OccurrencePlanning

  @doc """
  Creates an occurrence planning record.

  ## Examples

      iex> create(%{event_id: 1, poll_id: 2, series_type: "movie", series_id: 123})
      {:ok, %OccurrencePlanning{}}

      iex> create(%{event_id: 1})
      {:error, %Ecto.Changeset{}}

  """
  def create(attrs) do
    %OccurrencePlanning{}
    |> OccurrencePlanning.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single occurrence planning record by ID.

  Raises `Ecto.NoResultsError` if the record does not exist.

  ## Examples

      iex> get!(123)
      %OccurrencePlanning{}

      iex> get!(456)
      ** (Ecto.NoResultsError)

  """
  def get!(id) do
    Repo.get!(OccurrencePlanning, id)
  end

  @doc """
  Gets a single occurrence planning record by ID, or nil if not found.

  ## Examples

      iex> get(123)
      %OccurrencePlanning{}

      iex> get(456)
      nil

  """
  def get(id) do
    Repo.get(OccurrencePlanning, id)
  end

  @doc """
  Gets occurrence planning by event_id.

  ## Examples

      iex> get_by_event(123)
      %OccurrencePlanning{}

      iex> get_by_event(456)
      nil

  """
  def get_by_event(event_id) do
    from(op in OccurrencePlanning,
      where: op.event_id == ^event_id
    )
    |> Repo.one()
  end

  @doc """
  Gets occurrence planning by poll_id.

  ## Examples

      iex> get_by_poll(123)
      %OccurrencePlanning{}

      iex> get_by_poll(456)
      nil

  """
  def get_by_poll(poll_id) do
    from(op in OccurrencePlanning,
      where: op.poll_id == ^poll_id
    )
    |> Repo.one()
  end

  @doc """
  Gets occurrence planning by event_id, raising if not found.

  ## Examples

      iex> get_by_event!(123)
      %OccurrencePlanning{}

      iex> get_by_event!(456)
      ** (Ecto.NoResultsError)

  """
  def get_by_event!(event_id) do
    from(op in OccurrencePlanning,
      where: op.event_id == ^event_id
    )
    |> Repo.one!()
  end

  @doc """
  Gets occurrence planning by poll_id, raising if not found.

  ## Examples

      iex> get_by_poll!(123)
      %OccurrencePlanning{}

      iex> get_by_poll!(456)
      ** (Ecto.NoResultsError)

  """
  def get_by_poll!(poll_id) do
    from(op in OccurrencePlanning,
      where: op.poll_id == ^poll_id
    )
    |> Repo.one!()
  end

  @doc """
  Lists all occurrence planning records for a series.

  ## Examples

      iex> list_for_series("movie", 123)
      [%OccurrencePlanning{}, ...]

  """
  def list_for_series(series_type, series_id) do
    from(op in OccurrencePlanning,
      where: op.series_type == ^series_type and op.series_id == ^series_id,
      order_by: [desc: op.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all occurrence planning records that haven't been finalized yet.

  ## Examples

      iex> list_pending()
      [%OccurrencePlanning{}, ...]

  """
  def list_pending do
    from(op in OccurrencePlanning,
      where: is_nil(op.event_plan_id),
      order_by: [desc: op.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all occurrence planning records that have been finalized.

  ## Examples

      iex> list_finalized()
      [%OccurrencePlanning{}, ...]

  """
  def list_finalized do
    from(op in OccurrencePlanning,
      where: not is_nil(op.event_plan_id),
      order_by: [desc: op.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Updates an occurrence planning record.

  ## Examples

      iex> update(occurrence_planning, %{series_id: 456})
      {:ok, %OccurrencePlanning{}}

      iex> update(occurrence_planning, %{event_id: nil})
      {:error, %Ecto.Changeset{}}

  """
  def update(%OccurrencePlanning{} = occurrence_planning, attrs) do
    occurrence_planning
    |> OccurrencePlanning.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Finalizes an occurrence planning by linking it to an event_plan.

  ## Examples

      iex> finalize(occurrence_planning, event_plan_id)
      {:ok, %OccurrencePlanning{}}

      iex> finalize(occurrence_planning, nil)
      {:error, %Ecto.Changeset{}}

  """
  def finalize(%OccurrencePlanning{} = occurrence_planning, event_plan_id) do
    occurrence_planning
    |> OccurrencePlanning.finalization_changeset(event_plan_id)
    |> Repo.update()
  end

  @doc """
  Checks if an occurrence planning record is finalized.

  ## Examples

      iex> finalized?(%OccurrencePlanning{event_plan_id: 123})
      true

      iex> finalized?(%OccurrencePlanning{event_plan_id: nil})
      false

  """
  def finalized?(%OccurrencePlanning{event_plan_id: nil}), do: false
  def finalized?(%OccurrencePlanning{event_plan_id: _}), do: true

  @doc """
  Checks if an event has an occurrence planning record.

  ## Examples

      iex> has_occurrence_planning?(123)
      true

      iex> has_occurrence_planning?(456)
      false

  """
  def has_occurrence_planning?(event_id) do
    from(op in OccurrencePlanning,
      where: op.event_id == ^event_id
    )
    |> Repo.exists?()
  end

  @doc """
  Deletes an occurrence planning record.

  ## Examples

      iex> delete(occurrence_planning)
      {:ok, %OccurrencePlanning{}}

      iex> delete(occurrence_planning)
      {:error, %Ecto.Changeset{}}

  """
  def delete(%OccurrencePlanning{} = occurrence_planning) do
    Repo.delete(occurrence_planning)
  end

  @doc """
  Preloads associations on an occurrence planning record.

  ## Examples

      iex> preload(occurrence_planning, [:event, :poll, :event_plan])
      %OccurrencePlanning{event: %Event{}, poll: %Poll{}, ...}

  """
  def preload(%OccurrencePlanning{} = occurrence_planning, preloads) do
    Repo.preload(occurrence_planning, preloads)
  end
end
