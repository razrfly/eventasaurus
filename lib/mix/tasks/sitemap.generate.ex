defmodule Mix.Tasks.Sitemap.Generate do
  use Mix.Task
  require Logger

  @shortdoc "Generates XML sitemap for the Eventasaurus website"

  @moduledoc """
  Generates an XML sitemap for the Eventasaurus website.

  This task uses the Sitemapper library to generate a sitemap
  for activities (Phase 1), and will include cities, venues, and other
  content in future phases.

  The sitemap will be stored based on the environment:
  - In development: stored in the local filesystem (priv/static/sitemaps/)
  - In production: stored in an S3 bucket (Tigris/Fly.io)

  ## Options

  * `--s3` - Force S3 storage even in development environment

  ## Examples

      # Generate sitemap using default storage (local in dev, S3 in prod)
      $ mix sitemap.generate

      # Force S3 storage even in development
      $ mix sitemap.generate --s3
  """

  @impl Mix.Task
  def run(args) do
    # Parse args
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [s3: :boolean, host: :string, env: :string]
      )

    use_s3 = Keyword.get(opts, :s3, false)
    host = Keyword.get(opts, :host, "eventasaurus.com")
    env = Keyword.get(opts, :env, if(use_s3, do: "prod", else: nil))

    # Determine which apps to start based on storage type
    apps_to_start = [:logger, :ecto_sql, :postgrex]

    # If using S3, ensure the required dependencies are started
    if use_s3 do
      # Also start S3-specific applications
      [:ex_aws, :hackney] |> Enum.each(&Application.ensure_all_started/1)
    end

    # Start all required apps
    Enum.each(apps_to_start, &Application.ensure_all_started/1)

    # Start your application to make sure the database and other services are ready
    {:ok, _} = Application.ensure_all_started(:eventasaurus)

    # Build sitemap options
    sitemap_opts =
      []
      |> maybe_add_opt(:environment, env && String.to_atom(env))
      |> maybe_add_opt(:host, use_s3 && host)

    if use_s3 do
      Logger.info("Using S3 storage as requested via --s3 flag")
      Logger.info("Using host: #{host} for sitemap URLs")
    end

    Logger.info("Starting sitemap generation task")

    # Generate and persist the sitemap with explicit options
    case Eventasaurus.Sitemap.generate_and_persist(sitemap_opts) do
      :ok ->
        Logger.info("Sitemap generation task completed successfully")

        # If using S3, verify the upload
        if use_s3 do
          Logger.info("Verifying S3 upload...")
          Eventasaurus.Sitemap.test_s3_connectivity(sitemap_opts)
        end

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
