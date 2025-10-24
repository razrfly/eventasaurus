defmodule EventasaurusDiscovery.Sources.Source do
  use Ecto.Schema
  import Ecto.Changeset

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
    |> validate_format(:logo_url, ~r/^https?:\/\/\S+$/i, message: "must be a valid URL")
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
end
