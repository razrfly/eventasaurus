defmodule EventasaurusDiscovery.Categories.TranslationLearner do
  @moduledoc """
  Dynamically learns and stores translations from external sources.
  Instead of hardcoding translations, this module captures them as they're encountered.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.Category

  @doc """
  Learn a translation from an external source.
  When we map an external category name to an internal category,
  we can capture that external name as a translation.

  ## Examples
      iex> learn_translation("concerts", "koncerty", "pl", "Karnet")
      {:ok, %Category{}}
  """
  def learn_translation(category_slug, external_name, locale, source) when locale != "en" do
    case Repo.get_by(Category, slug: category_slug) do
      nil ->
        {:error, :category_not_found}

      category ->
        # Get existing translations or start with empty map
        translations = category.translations || %{}

        # Get existing translations for this locale
        locale_translations = Map.get(translations, locale, %{})

        # Only update if we don't have a name yet, or if this is a new variant
        updated_locale = case Map.get(locale_translations, "name") do
          nil ->
            # No translation yet, add it
            Map.put(locale_translations, "name", external_name)

          existing when existing == external_name ->
            # Same translation already exists
            locale_translations

          _different ->
            # Different translation exists - store as alternate
            alternates = Map.get(locale_translations, "alternates", [])
            if external_name in alternates do
              locale_translations
            else
              Map.put(locale_translations, "alternates", [external_name | alternates])
            end
        end

        # Add source information
        sources = Map.get(updated_locale, "sources", [])
        updated_locale = if source in sources do
          updated_locale
        else
          Map.put(updated_locale, "sources", [source | sources])
        end

        # Update the translations
        updated_translations = Map.put(translations, locale, updated_locale)

        # Save to database
        category
        |> Category.changeset(%{translations: updated_translations})
        |> Repo.update()
    end
  end

  def learn_translation(_category_slug, _external_name, "en", _source) do
    # Don't need to learn English translations - they're the base
    {:ok, :english_base}
  end

  @doc """
  Learn translations from a category mapping.
  Called when we successfully map an external category to an internal one.
  """
  def learn_from_mapping(category_id, external_value, external_locale, external_source) do
    category = Repo.get!(Category, category_id)

    if external_locale && external_locale != "en" do
      learn_translation(category.slug, external_value, external_locale, external_source)
    else
      {:ok, category}
    end
  end

  @doc """
  Get all learned translations for a category.
  """
  def get_translations(category_slug) do
    case Repo.get_by(Category, slug: category_slug) do
      nil -> %{}
      category -> category.translations || %{}
    end
  end

  @doc """
  Check if we've learned a specific translation.
  """
  def has_translation?(category_slug, locale) do
    translations = get_translations(category_slug)
    Map.has_key?(translations, locale)
  end

  @doc """
  Get statistics about learned translations.
  """
  def translation_stats do
    categories = Repo.all(Category)

    Enum.map(categories, fn category ->
      translations = category.translations || %{}
      locales = Map.keys(translations)

      %{
        category: category.slug,
        name: category.name,
        translation_count: length(locales),
        locales: locales,
        sources: Enum.flat_map(locales, fn locale ->
          Map.get(translations[locale], "sources", [])
        end) |> Enum.uniq()
      }
    end)
  end
end