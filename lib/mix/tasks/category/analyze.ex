defmodule Mix.Tasks.Category.Analyze do
  use Mix.Task

  @shortdoc "Analyze category patterns for discovery sources"

  @moduledoc """
  Analyze events categorized as "Other" to identify patterns and suggest improvements.

  ## Examples

      # Analyze single source
      mix category.analyze sortiraparis

      # Get JSON output
      mix category.analyze sortiraparis --json

  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [json: :boolean],
        aliases: [j: :json]
      )

    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.PublicEvents.PublicEvent
    alias EventasaurusDiscovery.Categories.Category
    alias EventasaurusDiscovery.Admin.PatternAnalyzer
    import Ecto.Query

    cond do
      length(args) > 0 ->
        # Analyze specific source
        source_slug = List.first(args)
        source = get_source(source_slug)

        if source do
          # Get statistics
          total_events = count_total_events(source.id)
          other_events = get_other_events(source.id)
          other_count = length(other_events)

          percentage =
            if total_events > 0 do
              Float.round(other_count / total_events * 100, 1)
            else
              0.0
            end

          # Analyze patterns
          patterns =
            if other_count > 0 do
              PatternAnalyzer.analyze_patterns(other_events)
            else
              nil
            end

          # Get available categories
          available_categories = get_available_categories()

          # Generate suggestions
          suggestions =
            if patterns do
              PatternAnalyzer.generate_suggestions(patterns, available_categories)
            else
              []
            end

          if opts[:json] do
            print_json(%{
              source: source_slug,
              total_events: total_events,
              other_events: other_count,
              percentage: percentage,
              patterns: format_patterns_for_json(patterns),
              suggestions: format_suggestions_for_json(suggestions),
              status: categorization_status(percentage)
            })
          else
            print_category_analysis(source_slug, total_events, other_count, percentage, patterns, suggestions)
          end
        else
          Mix.shell().error("Source not found: #{source_slug}")
          exit({:shutdown, 1})
        end

      true ->
        Mix.shell().info("Usage: mix category.analyze [source] [--json]")
        Mix.shell().info("")
        Mix.shell().info("Examples:")
        Mix.shell().info("  mix category.analyze sortiraparis")
        Mix.shell().info("  mix category.analyze sortiraparis --json")
    end
  end

  defp get_source(slug) do
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Sources.Source
    import Ecto.Query

    query =
      from s in Source,
        where: s.slug == ^slug,
        select: %{id: s.id, name: s.name, slug: s.slug}

    Repo.one(query)
  end

  defp count_total_events(source_id) do
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.PublicEvents.PublicEvent
    import Ecto.Query

    query =
      from e in PublicEvent,
        join: pes in assoc(e, :sources),
        where: pes.source_id == ^source_id,
        select: count(fragment("DISTINCT ?", e.id))

    Repo.one(query) || 0
  end

  defp get_other_events(source_id) do
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.PublicEvents.PublicEvent
    alias EventasaurusDiscovery.Categories.Category
    import Ecto.Query

    other_category_id =
      Repo.one(
        from c in Category,
          where: c.slug == "other" and c.is_active == true,
          select: c.id,
          limit: 1
      )

    if other_category_id do
      query =
        from e in PublicEvent,
          join: pes in assoc(e, :sources),
          join: pec in "public_event_categories",
          on: pec.event_id == e.id,
          left_join: v in "venues",
          on: v.id == e.venue_id,
          where: pes.source_id == ^source_id,
          where: pec.category_id == ^other_category_id,
          distinct: [e.id],
          select: %{
            id: e.id,
            title: e.title,
            source_url: pes.source_url,
            venue_name: v.name,
            venue_type: v.venue_type,
            inserted_at: e.inserted_at
          },
          order_by: [asc: e.id, desc: e.inserted_at],
          limit: 500

      Repo.all(query)
    else
      []
    end
  end

  defp get_available_categories do
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Categories.Category
    import Ecto.Query

    query =
      from c in Category,
        where: c.is_active == true and c.slug != "other",
        select: %{id: c.id, name: c.name, slug: c.slug},
        order_by: c.name

    Repo.all(query)
  end

  defp print_category_analysis(source_slug, total_events, other_count, percentage, patterns, suggestions) do
    Mix.shell().info("\n" <> IO.ANSI.bright() <> "Category Analysis: #{source_slug}" <> IO.ANSI.reset())
    Mix.shell().info("=" |> String.duplicate(60))
    Mix.shell().info("")

    # Summary statistics
    Mix.shell().info(IO.ANSI.bright() <> "Summary Statistics:" <> IO.ANSI.reset())
    Mix.shell().info("  Total Events:    #{format_number(total_events)}")
    Mix.shell().info("  'Other' Events:  #{format_number(other_count)}")

    status_color = if percentage < 10, do: IO.ANSI.green(), else: IO.ANSI.red()
    status_text = if percentage < 10, do: "✓ Good", else: "✗ Needs improvement"

    Mix.shell().info("  Percentage:      " <> status_color <> "#{percentage}%" <> IO.ANSI.reset() <> " (Target: <10% - #{status_text})")
    Mix.shell().info("")

    if other_count > 0 and patterns do
      # Suggestions
      if length(suggestions) > 0 do
        Mix.shell().info(IO.ANSI.bright() <> "💡 Suggested Category Mappings:" <> IO.ANSI.reset())
        Mix.shell().info("")

        Enum.each(suggestions, fn suggestion ->
          confidence_color = confidence_color(suggestion.confidence)
          confidence_label = confidence_label(suggestion.confidence)

          Mix.shell().info("  " <> IO.ANSI.bright() <> suggestion.category <> IO.ANSI.reset())
          Mix.shell().info("    Confidence: " <> confidence_color <> confidence_label <> IO.ANSI.reset())
          Mix.shell().info("    Would categorize: #{suggestion.event_count} events")

          if length(suggestion.url_patterns) > 0 do
            Mix.shell().info("    URL patterns: " <> Enum.join(suggestion.url_patterns, ", "))
          end

          if length(suggestion.keywords) > 0 do
            Mix.shell().info("    Keywords: " <> Enum.join(suggestion.keywords, ", "))
          end

          Mix.shell().info("")
        end)
      end

      # Top URL patterns
      if length(patterns.url_patterns) > 0 do
        Mix.shell().info(IO.ANSI.bright() <> "🔗 Top URL Patterns:" <> IO.ANSI.reset())
        Enum.take(patterns.url_patterns, 5) |> Enum.each(fn pattern ->
          Mix.shell().info("  /#{pattern.pattern}/ - #{pattern.count} events (#{pattern.percentage}%)")
        end)
        Mix.shell().info("")
      end

      # Top keywords
      if length(patterns.title_keywords) > 0 do
        Mix.shell().info(IO.ANSI.bright() <> "🏷️  Top Title Keywords:" <> IO.ANSI.reset())
        Enum.take(patterns.title_keywords, 5) |> Enum.each(fn keyword ->
          Mix.shell().info("  #{keyword.keyword} - #{keyword.count} events (#{keyword.percentage}%)")
        end)
        Mix.shell().info("")
      end

      # Venue types
      if length(patterns.venue_types) > 0 do
        Mix.shell().info(IO.ANSI.bright() <> "🏛️  Venue Types:" <> IO.ANSI.reset())
        Enum.take(patterns.venue_types, 5) |> Enum.each(fn venue_type ->
          Mix.shell().info("  #{venue_type.venue_type} - #{venue_type.count} events (#{venue_type.percentage}%)")
        end)
        Mix.shell().info("")
      end

      # Next steps
      Mix.shell().info(IO.ANSI.blue() <> "Next Steps:" <> IO.ANSI.reset())
      Mix.shell().info("  1. Review patterns and suggestions above")
      Mix.shell().info("  2. Update priv/category_mappings/#{source_slug}.yml")
      Mix.shell().info("  3. Run: mix eventasaurus.recategorize_events --source #{source_slug}")
      Mix.shell().info("  4. Re-run this analysis to verify improvements")
    else
      Mix.shell().info(IO.ANSI.green() <> "✅ Excellent! No events categorized as 'Other'." <> IO.ANSI.reset())
    end
  end

  defp format_patterns_for_json(nil), do: nil

  defp format_patterns_for_json(patterns) do
    %{
      url_patterns: patterns.url_patterns,
      title_keywords: patterns.title_keywords,
      venue_types: patterns.venue_types
    }
  end

  defp format_suggestions_for_json(suggestions) do
    Enum.map(suggestions, fn suggestion ->
      %{
        category: suggestion.category,
        category_slug: suggestion.category_slug,
        url_patterns: suggestion.url_patterns,
        keywords: suggestion.keywords,
        event_count: suggestion.event_count,
        confidence: Atom.to_string(suggestion.confidence),
        yaml: suggestion.yaml,
        sample_events: Enum.map(suggestion.sample_events, &%{id: &1.id, title: &1.title})
      }
    end)
  end

  defp categorization_status(percentage) when percentage < 10, do: "excellent"
  defp categorization_status(percentage) when percentage < 20, do: "good"
  defp categorization_status(percentage) when percentage < 30, do: "needs_improvement"
  defp categorization_status(_), do: "poor"

  defp confidence_color(:high), do: IO.ANSI.green()
  defp confidence_color(:medium), do: IO.ANSI.yellow()
  defp confidence_color(:low), do: IO.ANSI.light_black()

  defp confidence_label(:high), do: "High"
  defp confidence_label(:medium), do: "Medium"
  defp confidence_label(:low), do: "Low"

  defp print_json(data) do
    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(_), do: "0"
end
