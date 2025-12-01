defmodule Mix.Tasks.Sitemap.Generate do
  use Mix.Task
  require Logger

  @shortdoc "Generates XML sitemap for the Wombie website"

  @moduledoc """
  Generates an XML sitemap for the Wombie website.

  This task uses the Sitemapper library to generate a sitemap
  for activities (Phase 1), and will include cities, venues, and other
  content in future phases.

  The sitemap will be stored based on the environment:
  - In development: stored in the local filesystem (priv/static/sitemaps/)
  - In production: stored in Cloudflare R2 (served via CDN at cdn2.wombie.com/sitemaps/)

  ## Options

  * `--prod` - Force production storage (R2) even in development environment
  * `--host` - Override host for URL generation (default: wombie.com)

  ## Examples

      # Generate sitemap using default storage (local in dev, R2 in prod)
      $ mix sitemap.generate

      # Force R2 storage even in development
      $ mix sitemap.generate --prod --host wombie.com
  """

  @impl Mix.Task
  def run(args) do
    # Parse args
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [prod: :boolean, host: :string, env: :string]
      )

    use_prod = Keyword.get(opts, :prod, false)
    host = Keyword.get(opts, :host, "wombie.com")
    env = Keyword.get(opts, :env, if(use_prod, do: "prod", else: nil))

    # Start required apps
    apps_to_start = [:logger, :ecto_sql, :postgrex, :hackney]
    Enum.each(apps_to_start, &Application.ensure_all_started/1)

    # Start your application to make sure the database and other services are ready
    {:ok, _} = Application.ensure_all_started(:eventasaurus)

    # Build sitemap options
    sitemap_opts =
      []
      |> maybe_add_opt(:environment, env && String.to_atom(env))
      |> maybe_add_opt(:host, use_prod && host)

    if use_prod do
      Logger.info("Using R2 Storage as requested via --prod flag")
      Logger.info("Using host: #{host} for sitemap URLs")
    end

    Logger.info("Starting sitemap generation task")

    # Generate and persist the sitemap with explicit options
    case Eventasaurus.Sitemap.generate_and_persist(sitemap_opts) do
      :ok ->
        Logger.info("Sitemap generation task completed successfully")
        :ok

      {:error, error} ->
        Logger.error("Sitemap generation task failed: #{inspect(error, pretty: true)}")
        exit({:shutdown, 1})
    end
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, false), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
