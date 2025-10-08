defmodule EventasaurusDiscovery.Locations.City.DiscoveryConfig do
  @moduledoc """
  Embedded schema for city discovery automation configuration.

  Provides type-safe access to discovery settings stored in the JSONB
  `discovery_config` field on cities table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one :schedule, Schedule, primary_key: false, on_replace: :update do
      field(:cron, :string, default: "0 0 * * *")
      field(:timezone, :string, default: "UTC")
      field(:enabled, :boolean, default: true)
    end

    embeds_many :sources, Source, on_replace: :delete do
      field(:name, :string)
      field(:enabled, :boolean, default: true)
      field(:frequency_hours, :integer, default: 24)
      field(:settings, :map, default: %{})
      field(:last_run_at, :utc_datetime)
      field(:next_run_at, :utc_datetime)

      embeds_one :stats, Stats, primary_key: false, on_replace: :update do
        field(:run_count, :integer, default: 0)
        field(:success_count, :integer, default: 0)
        field(:error_count, :integer, default: 0)
        field(:last_error, :string)
      end
    end
  end

  @doc """
  Changeset for discovery configuration.
  """
  def changeset(config, attrs) do
    config
    |> cast(attrs, [])
    |> cast_embed(:schedule, with: &schedule_changeset/2)
    |> cast_embed(:sources, with: &source_changeset/2)
  end

  defp schedule_changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:cron, :timezone, :enabled])
    |> validate_required([:cron, :timezone])
    |> validate_inclusion(:timezone, Tzdata.zone_list())
  end

  defp source_changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :enabled, :frequency_hours, :settings, :last_run_at, :next_run_at])
    |> cast_embed(:stats, with: &stats_changeset/2)
    |> validate_required([:name])
    |> validate_inclusion(:name, valid_source_names())
    |> validate_number(:frequency_hours, greater_than: 0)
  end

  defp stats_changeset(stats, attrs) do
    stats
    |> cast(attrs, [:run_count, :success_count, :error_count, :last_error])
    |> validate_number(:run_count, greater_than_or_equal_to: 0)
    |> validate_number(:success_count, greater_than_or_equal_to: 0)
    |> validate_number(:error_count, greater_than_or_equal_to: 0)
  end

  @doc """
  Returns list of valid discovery source names.
  """
  def valid_source_names do
    [
      "ticketmaster",
      "bandsintown",
      "resident-advisor",
      "karnet",
      "kino-krakow",
      "cinema-city",
      "pubquiz-pl"
    ]
  end

  @doc """
  Returns default discovery configuration for a new city.
  """
  def default do
    %__MODULE__{
      schedule: %__MODULE__.Schedule{
        cron: "0 0 * * *",
        timezone: "UTC",
        enabled: true
      },
      sources: []
    }
  end

  @doc """
  Creates a new source configuration.
  """
  def new_source(name, settings \\ %{})
      when name in [
             "ticketmaster",
             "bandsintown",
             "resident-advisor",
             "karnet",
             "kino-krakow",
             "cinema-city",
             "pubquiz-pl"
           ] do
    %__MODULE__.Source{
      name: name,
      enabled: true,
      frequency_hours: 24,
      settings: settings,
      stats: %__MODULE__.Source.Stats{
        run_count: 0,
        success_count: 0,
        error_count: 0
      }
    }
  end
end
