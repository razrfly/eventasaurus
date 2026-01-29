defmodule EventasaurusDiscovery.Categories.CategoryMapping do
  @moduledoc """
  Schema for database-backed category mappings.

  Replaces YAML-based mappings with queryable database records.
  Supports both direct (exact match) and pattern (regex) mappings.

  ## Mapping Types

  - `direct` - Exact string match (case-insensitive)
  - `pattern` - Regex pattern match

  ## Sources

  - `_defaults` - Fallback mappings used when no source-specific mapping exists
  - `bandsintown`, `karnet`, `ticketmaster`, etc. - Source-specific mappings

  ## Examples

      # Direct mapping: "rock" -> "concerts"
      %CategoryMapping{
        source: "bandsintown",
        external_term: "rock",
        mapping_type: "direct",
        category_slug: "concerts"
      }

      # Pattern mapping: anything matching "jazz|blues" -> "concerts"
      %CategoryMapping{
        source: "_defaults",
        external_term: "jazz|blues|soul",
        mapping_type: "pattern",
        category_slug: "concerts",
        priority: 10
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type mapping_type :: String.t()

  @mapping_types ~w(direct pattern)

  schema "category_mappings" do
    field :source, :string
    field :external_term, :string
    field :mapping_type, :string
    field :category_slug, :string
    field :priority, :integer, default: 0
    field :is_active, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :created_by, EventasaurusApp.Accounts.User

    timestamps()
  end

  @doc """
  Creates a changeset for a new or existing category mapping.
  """
  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [
      :source,
      :external_term,
      :mapping_type,
      :category_slug,
      :priority,
      :is_active,
      :created_by_id,
      :metadata
    ])
    |> validate_required([:source, :external_term, :mapping_type, :category_slug])
    |> validate_inclusion(:mapping_type, @mapping_types,
      message: "must be 'direct' or 'pattern'"
    )
    |> validate_length(:source, max: 50)
    |> validate_length(:external_term, max: 255)
    |> validate_length(:category_slug, max: 100)
    |> normalize_external_term()
    |> validate_pattern_syntax()
    |> unique_constraint([:source, :external_term, :mapping_type],
      name: :category_mappings_source_term_type_unique,
      message: "mapping already exists for this source and term"
    )
  end

  @doc """
  Creates a changeset for importing from YAML (no user tracking).
  """
  def import_changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [
      :source,
      :external_term,
      :mapping_type,
      :category_slug,
      :priority,
      :is_active,
      :metadata
    ])
    |> validate_required([:source, :external_term, :mapping_type, :category_slug])
    |> validate_inclusion(:mapping_type, @mapping_types)
    |> normalize_external_term()
    |> validate_pattern_syntax()
    |> unique_constraint([:source, :external_term, :mapping_type],
      name: :category_mappings_source_term_type_unique
    )
  end

  # Normalize external_term for direct mappings (lowercase, trimmed)
  defp normalize_external_term(changeset) do
    case get_change(changeset, :external_term) do
      nil ->
        changeset

      term ->
        mapping_type = get_field(changeset, :mapping_type)

        if mapping_type == "direct" do
          put_change(changeset, :external_term, String.downcase(String.trim(term)))
        else
          # Keep patterns as-is (they're case-insensitive regex)
          put_change(changeset, :external_term, String.trim(term))
        end
    end
  end

  # Validate that pattern mappings have valid regex syntax
  defp validate_pattern_syntax(changeset) do
    mapping_type = get_field(changeset, :mapping_type)
    external_term = get_field(changeset, :external_term)

    if mapping_type == "pattern" && external_term do
      case Regex.compile(external_term, "i") do
        {:ok, _} ->
          changeset

        {:error, {reason, _}} ->
          add_error(changeset, :external_term, "invalid regex pattern: #{reason}")
      end
    else
      changeset
    end
  end

  @doc """
  Returns the list of valid mapping types.
  """
  def mapping_types, do: @mapping_types

  @doc """
  Checks if a mapping is a pattern (regex) mapping.
  """
  def pattern?(%__MODULE__{mapping_type: "pattern"}), do: true
  def pattern?(%__MODULE__{}), do: false

  @doc """
  Checks if a mapping is a direct (exact match) mapping.
  """
  def direct?(%__MODULE__{mapping_type: "direct"}), do: true
  def direct?(%__MODULE__{}), do: false
end
