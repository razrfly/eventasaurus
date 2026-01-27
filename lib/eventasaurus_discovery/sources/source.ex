defmodule EventasaurusDiscovery.Sources.Source do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias EventasaurusApp.Repo

  @allowed_domains ~w[
    music
    concert
    sports
    theater
    comedy
    dance
    food
    business
    education
    exhibition
    festival
    literary
    screening
    movies
    cinema
    social
    visual-arts
    cultural
    trivia
    general
  ]

  def allowed_domains, do: @allowed_domains

  schema "sources" do
    field(:name, :string)
    field(:slug, :string)
    field(:website_url, :string)
    field(:priority, :integer, default: 50)
    field(:is_active, :boolean, default: true)
    field(:metadata, :map, default: %{})
    field(:domains, {:array, :string}, default: ["general"])
    field(:aggregate_on_index, :boolean, default: false)
    field(:aggregation_type, :string)
    field(:logo_url, :string)

    has_many(:public_event_sources, EventasaurusDiscovery.PublicEvents.PublicEventSource)

    timestamps()
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :name,
      :slug,
      :website_url,
      :priority,
      :is_active,
      :metadata,
      :domains,
      :aggregate_on_index,
      :aggregation_type,
      :logo_url
    ])
    |> validate_required([:name, :slug])
    |> update_change(:slug, &(&1 && String.downcase(&1)))
    |> validate_format(:website_url, ~r/^https?:\/\/\S+$/i,
      message: "must start with http:// or https://"
    )
    |> validate_logo_url()
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_domains()
    |> unique_constraint(:slug)
  end

  defp validate_domains(changeset) do
    changeset
    |> validate_change(:domains, fn :domains, domains ->
      cond do
        not is_list(domains) ->
          [domains: "must be a list"]

        not Enum.all?(domains, &is_binary/1) ->
          [domains: "must be a list of strings"]

        Enum.empty?(domains) ->
          [domains: "must have at least one domain"]

        true ->
          invalid_domains = Enum.reject(domains, &(&1 in @allowed_domains))

          if Enum.empty?(invalid_domains) do
            []
          else
            [
              domains:
                "contains invalid domains: #{Enum.join(invalid_domains, ", ")}. " <>
                  "Allowed domains: #{Enum.join(@allowed_domains, ", ")}"
            ]
          end
      end
    end)
  end

  # Validates logo_url - accepts either full URLs (http/https) or local paths (/uploads/...)
  defp validate_logo_url(changeset) do
    validate_change(changeset, :logo_url, fn :logo_url, url ->
      cond do
        # Empty or nil is valid (logo is optional)
        is_nil(url) or url == "" ->
          []

        # Full URLs starting with http:// or https://
        String.match?(url, ~r/^https?:\/\/\S+$/i) ->
          []

        # Local paths starting with /uploads/
        String.starts_with?(url, "/uploads/") ->
          []

        # Local paths starting with just /
        String.starts_with?(url, "/") ->
          []

        true ->
          [logo_url: "must be a valid URL or local path"]
      end
    end)
  end

  @doc """
  Check if two sources have compatible domains for cross-source deduplication.

  Sources are compatible if they share at least one domain, OR if either source
  has "general" in its domains (general sources can match anything).

  ## Examples

      iex> source1 = %Source{domains: ["music", "concert"]}
      iex> source2 = %Source{domains: ["music", "electronic"]}
      iex> Source.domains_compatible?(source1, source2)
      true

      iex> source1 = %Source{domains: ["music"]}
      iex> source2 = %Source{domains: ["movies"]}
      iex> Source.domains_compatible?(source1, source2)
      false

      iex> source1 = %Source{domains: ["music"]}
      iex> source2 = %Source{domains: ["general"]}
      iex> Source.domains_compatible?(source1, source2)
      true
  """
  def domains_compatible?(%__MODULE__{domains: domains1}, %__MODULE__{domains: domains2}) do
    domains_compatible?(domains1, domains2)
  end

  def domains_compatible?(domains1, domains2) when is_list(domains1) and is_list(domains2) do
    # If either has "general", they're compatible with everything
    has_general = "general" in domains1 or "general" in domains2

    # Check if there's any overlap
    has_overlap = not MapSet.disjoint?(MapSet.new(domains1), MapSet.new(domains2))

    has_general or has_overlap
  end

  def domains_compatible?(_, _), do: false

  @doc """
  Get the display name for a source by its slug.

  This function queries the sources table and returns the `name` field for the given slug.
  If the source is not found in the database, it falls back to generating a display name
  from the slug by replacing hyphens/underscores with spaces and capitalizing each word.

  ## Parameters

    - `slug` - The source slug (e.g., "week_pl", "bandsintown", "pubquiz-pl")

  ## Returns

  The display name string (e.g., "Restaurant Week", "Bandsintown", "PubQuiz Poland")

  ## Examples

      iex> Source.get_display_name("week_pl")
      "Restaurant Week"

      iex> Source.get_display_name("bandsintown")
      "Bandsintown"

      iex> Source.get_display_name("unknown-source")
      "Unknown Source"

  ## Notes

  - This is the single source of truth for source display names
  - All hardcoded source name mappings should be replaced with this function
  - The fallback handles both hyphen-separated and underscore-separated slugs
  - Database queries are indexed by slug for performance

  """
  def get_display_name(slug) when is_binary(slug) do
    case Repo.one(from(s in __MODULE__, where: s.slug == ^slug, select: s.name)) do
      name when is_binary(name) -> name
      nil -> fallback_display_name(slug)
    end
  end

  def get_display_name(_), do: ""

  # Generate a display name from a slug when source is not found in database
  defp fallback_display_name(slug) do
    slug
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Convert a PascalCase module name to a canonical hyphenated slug.

  This is the single source of truth for converting module names to slugs.
  Database slugs use hyphens (e.g., "cinema-city", "resident-advisor").

  ## Parameters

    - `module_name` - PascalCase module name (e.g., "CinemaCity", "ResidentAdvisor")

  ## Returns

  The canonical hyphenated slug (e.g., "cinema-city", "resident-advisor")

  ## Examples

      iex> Source.module_name_to_slug("CinemaCity")
      "cinema-city"

      iex> Source.module_name_to_slug("ResidentAdvisor")
      "resident-advisor"

      iex> Source.module_name_to_slug("Bandsintown")
      "bandsintown"

  """
  def module_name_to_slug(module_name) when is_binary(module_name) do
    module_name
    |> Macro.underscore()
    |> String.replace("_", "-")
  end

  def module_name_to_slug(_), do: nil

  @doc """
  Extract the canonical source slug from an Oban worker module path.

  Parses worker names like "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob"
  and returns the canonical hyphenated slug (e.g., "cinema-city").

  ## Parameters

    - `worker` - Full worker module path string

  ## Returns

  The canonical slug or nil if the worker path doesn't match expected format.

  ## Examples

      iex> Source.worker_to_slug("EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob")
      "cinema-city"

      iex> Source.worker_to_slug("EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.EventDetailJob")
      "resident-advisor"

      iex> Source.worker_to_slug("SomeOtherWorker")
      nil

  """
  def worker_to_slug(worker) when is_binary(worker) do
    case Regex.run(~r/Sources\.(\w+)\.Jobs/, worker) do
      [_, module_name] -> module_name_to_slug(module_name)
      _ -> nil
    end
  end

  def worker_to_slug(_), do: nil

  @doc """
  Convert a slug (hyphenated or underscored) to a PascalCase module name.

  This handles both the canonical hyphenated format and legacy underscore format.

  ## Parameters

    - `slug` - Source slug (e.g., "cinema-city" or "cinema_city")

  ## Returns

  The PascalCase module name (e.g., "CinemaCity")

  ## Examples

      iex> Source.slug_to_module_name("cinema-city")
      "CinemaCity"

      iex> Source.slug_to_module_name("cinema_city")
      "CinemaCity"

      iex> Source.slug_to_module_name("bandsintown")
      "Bandsintown"

  """
  def slug_to_module_name(slug) when is_binary(slug) do
    slug
    |> String.split(~r/[-_]/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  def slug_to_module_name(_), do: nil
end
