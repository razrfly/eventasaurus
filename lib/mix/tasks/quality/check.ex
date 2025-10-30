defmodule Mix.Tasks.Quality.Check do
  use Mix.Task

  @shortdoc "Check data quality for discovery sources"

  @moduledoc """
  Check data quality for discovery sources.

  ## Examples

      # Check single source
      mix quality.check sortiraparis

      # List all sources with scores
      mix quality.check --all

      # Get JSON output
      mix quality.check sortiraparis --json

  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [all: :boolean, json: :boolean],
        aliases: [a: :all, j: :json]
      )

    alias EventasaurusDiscovery.Admin.DataQualityChecker
    alias EventasaurusDiscovery.Sources.SourceRegistry

    cond do
      opts[:all] ->
        # List all sources with quality scores
        sources = SourceRegistry.all_sources()

        results =
          Enum.map(sources, fn slug ->
            quality = DataQualityChecker.check_quality(slug)

            %{
              source: slug,
              score: quality.quality_score,
              total_events: quality.total_events
            }
          end)
          |> Enum.sort_by(& &1.score, :desc)

        if opts[:json] do
          print_json(%{sources: results})
        else
          print_all_sources(results)
        end

      length(args) > 0 ->
        # Check specific source
        source_slug = List.first(args)
        quality = DataQualityChecker.check_quality(source_slug)

        if Map.get(quality, :not_found, false) do
          Mix.shell().error("Source not found: #{source_slug}")
          exit({:shutdown, 1})
        end

        recommendations = DataQualityChecker.get_recommendations(source_slug)

        if opts[:json] do
          print_json(%{
            source: source_slug,
            quality_score: quality.quality_score,
            total_events: quality.total_events,
            metrics: %{
              venue_coverage: quality.venue_coverage,
              venue_name_quality: quality.venue_name_quality,
              venue_quality: quality.venue_quality,
              image: quality.image_completeness,
              category: quality.category_completeness,
              specificity: quality.category_specificity,
              price: quality.price_completeness,
              description: quality.description_quality,
              performer: quality.performer_completeness,
              occurrence: quality.occurrence_richness,
              translation: quality.translation_completeness
            },
            venue_details: %{
              missing_venues: quality.missing_venues,
              venues_with_low_quality_names: quality.venues_with_low_quality_names,
              low_quality_examples: quality.low_quality_venue_examples
            },
            recommendations: recommendations
          })
        else
          print_source_quality(source_slug, quality, recommendations)
        end

      true ->
        Mix.shell().info("Usage: mix quality.check [source] [--all] [--json]")
        Mix.shell().info("")
        Mix.shell().info("Examples:")
        Mix.shell().info("  mix quality.check sortiraparis")
        Mix.shell().info("  mix quality.check --all")
        Mix.shell().info("  mix quality.check sortiraparis --json")
    end
  end

  defp print_all_sources(results) do
    Mix.shell().info(
      "\n" <> IO.ANSI.bright() <> "Quality Scores - All Sources" <> IO.ANSI.reset()
    )

    Mix.shell().info("=" |> String.duplicate(60))
    Mix.shell().info("")

    alias EventasaurusDiscovery.Admin.DataQualityChecker

    Enum.each(results, fn result ->
      {emoji, _text, _class} = DataQualityChecker.quality_status(result.score)
      color = score_color(result.score)

      Mix.shell().info(
        color <>
          "#{emoji} #{result.source}" <>
          IO.ANSI.reset() <>
          " - " <>
          color <>
          "#{result.score}%" <>
          IO.ANSI.reset() <>
          " (#{format_number(result.total_events)} events)"
      )
    end)

    avg_score =
      if length(results) > 0 do
        (Enum.reduce(results, 0, fn r, acc -> acc + r.score end) / length(results)) |> round()
      else
        0
      end

    Mix.shell().info("")
    Mix.shell().info("=" |> String.duplicate(60))
    Mix.shell().info("Average Score: #{avg_score}% | Sources: #{length(results)}")
  end

  defp print_source_quality(source_slug, quality, recommendations) do
    alias EventasaurusDiscovery.Admin.DataQualityChecker
    {emoji, status_text, _class} = DataQualityChecker.quality_status(quality.quality_score)
    color = score_color(quality.quality_score)

    Mix.shell().info(
      "\n" <> IO.ANSI.bright() <> "Quality Report: #{source_slug}" <> IO.ANSI.reset()
    )

    Mix.shell().info("=" |> String.duplicate(60))

    Mix.shell().info(
      "Overall Score: " <>
        color <> "#{quality.quality_score}% #{emoji} #{status_text}" <> IO.ANSI.reset()
    )

    Mix.shell().info("")

    Mix.shell().info(IO.ANSI.bright() <> "Dimensions:" <> IO.ANSI.reset())
    print_venue_quality(quality)
    print_dimension("Image", quality.image_completeness)
    print_dimension("Category", quality.category_completeness)
    print_dimension("Specificity", quality.category_specificity)
    print_dimension("Price", quality.price_completeness)
    print_dimension("Description", quality.description_quality)
    print_dimension("Performer", quality.performer_completeness)
    print_dimension("Occurrence", quality.occurrence_richness)

    if quality.supports_translations do
      print_dimension("Translation", quality.translation_completeness)
    end

    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.bright() <> "Issues Found:" <> IO.ANSI.reset())

    if Enum.any?(recommendations, &(&1 != "Data quality is excellent! 🎉")) do
      Enum.each(recommendations, fn rec ->
        if rec != "Data quality is excellent! 🎉" do
          Mix.shell().info("  #{IO.ANSI.yellow()}•#{IO.ANSI.reset()} #{rec}")
        end
      end)
    else
      Mix.shell().info(
        "  #{IO.ANSI.green()}✓ No issues found - data quality is excellent!#{IO.ANSI.reset()}"
      )
    end

    Mix.shell().info("")
    Mix.shell().info("Total Events: #{format_number(quality.total_events)}")
  end

  defp print_dimension(name, score) when is_nil(score) do
    Mix.shell().info("  #{String.pad_trailing(name <> ":", 15)} N/A")
  end

  defp print_dimension(name, score) do
    color = score_color(score)
    indicator = score_indicator(score)

    Mix.shell().info(
      "  #{String.pad_trailing(name <> ":", 15)} " <>
        color <>
        "#{String.pad_leading("#{score}%", 4)}" <>
        IO.ANSI.reset() <>
        " #{indicator}"
    )
  end

  defp print_venue_quality(quality) do
    # Print overall venue quality
    print_dimension("Venue (Overall)", quality.venue_quality)

    # Print breakdown
    coverage_color = score_color(quality.venue_coverage)
    coverage_indicator = score_indicator(quality.venue_coverage)

    Mix.shell().info(
      "    #{IO.ANSI.faint()}└ Coverage:#{IO.ANSI.reset()}    " <>
        coverage_color <>
        "#{String.pad_leading("#{quality.venue_coverage}%", 4)}" <>
        IO.ANSI.reset() <>
        " #{coverage_indicator} " <>
        IO.ANSI.faint() <>
        "(#{quality.missing_venues} missing)" <>
        IO.ANSI.reset()
    )

    quality_color = score_color(quality.venue_name_quality)
    quality_indicator = score_indicator(quality.venue_name_quality)

    Mix.shell().info(
      "    #{IO.ANSI.faint()}└ Name Quality:#{IO.ANSI.reset()} " <>
        quality_color <>
        "#{String.pad_leading("#{quality.venue_name_quality}%", 4)}" <>
        IO.ANSI.reset() <>
        " #{quality_indicator}"
    )

    # Show examples if there are low quality names
    if quality.venues_with_low_quality_names > 0 do
      Mix.shell().info(
        "      #{IO.ANSI.yellow()}⚠️  #{quality.venues_with_low_quality_names} venues with low-quality names#{IO.ANSI.reset()}"
      )

      # Show first 3 examples
      quality.low_quality_venue_examples
      |> Enum.take(3)
      |> Enum.each(fn example ->
        severity_color =
          if Map.get(example, :severity) == :moderate, do: IO.ANSI.yellow(), else: IO.ANSI.red()

        severity_text =
          if Map.get(example, :severity) == :moderate, do: "moderate", else: "severe"

        Mix.shell().info(
          "      #{IO.ANSI.faint()}•#{IO.ANSI.reset()} " <>
            severity_color <>
            "\"#{String.slice(example.venue_name, 0..40)}\"" <>
            IO.ANSI.reset() <>
            " vs " <>
            IO.ANSI.green() <>
            "\"#{String.slice(example.geocoded_name, 0..40)}\"" <>
            IO.ANSI.reset() <>
            IO.ANSI.faint() <>
            " (similarity: #{Float.round(example.similarity, 2)}, #{severity_text})" <>
            IO.ANSI.reset()
        )
      end)
    end
  end

  defp score_color(score) when score >= 90, do: IO.ANSI.green()
  defp score_color(score) when score >= 75, do: IO.ANSI.yellow()
  defp score_color(score) when score >= 60, do: IO.ANSI.light_yellow()
  defp score_color(_), do: IO.ANSI.red()

  defp score_indicator(score) when score >= 90, do: "✅"
  defp score_indicator(score) when score >= 75, do: "✅"
  defp score_indicator(score) when score >= 60, do: "⚠️"
  defp score_indicator(_), do: "🔴"

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
