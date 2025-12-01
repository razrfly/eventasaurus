# Migrate files from Supabase Storage to Cloudflare R2
#
# This script:
# 1. Lists all files in Supabase Storage bucket
# 2. Downloads each file
# 3. Uploads to R2 bucket preserving folder structure
#
# Usage: mix run priv/scripts/migrate_supabase_to_r2.exs
#
# Options:
#   --dry-run    Show what would be migrated without actually doing it
#   --folder     Only migrate a specific folder (events, sitemaps, sources, groups, avatars)
#
# Example:
#   mix run priv/scripts/migrate_supabase_to_r2.exs --dry-run
#   mix run priv/scripts/migrate_supabase_to_r2.exs --folder sitemaps

defmodule SupabaseToR2Migration do
  require Logger

  # Supabase Storage configuration
  @supabase_bucket "eventasaur.us"
  @folders ["events", "sitemaps", "sources", "groups", "avatars"]

  # R2 configuration
  @r2_bucket "wombie"
  @cdn_url "https://cdn2.wombie.com"

  # Retry configuration
  @max_retries 3
  @base_delay_ms 2000

  def run(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    folder_filter = Keyword.get(opts, :folder, nil)

    IO.puts("\n=== Supabase to R2 Migration ===\n")

    if dry_run do
      IO.puts("*** DRY RUN MODE - No files will be transferred ***\n")
    end

    # Wait for application startup to complete to avoid rate limits
    IO.puts("Waiting 3s for application startup to settle...")
    Process.sleep(3000)

    # Load and validate credentials
    with {:ok, supabase_config} <- load_supabase_config(),
         {:ok, r2_config} <- load_r2_config() do
      folders =
        if folder_filter do
          if folder_filter in @folders do
            [folder_filter]
          else
            IO.puts("Invalid folder: #{folder_filter}")
            IO.puts("Valid folders: #{Enum.join(@folders, ", ")}")
            System.halt(1)
          end
        else
          @folders
        end

      IO.puts("Supabase bucket: #{@supabase_bucket}")
      IO.puts("R2 bucket: #{@r2_bucket}")
      IO.puts("Folders to migrate: #{Enum.join(folders, ", ")}\n")

      # Migrate each folder
      results =
        Enum.map(folders, fn folder ->
          migrate_folder(folder, supabase_config, r2_config, dry_run)
        end)

      # Print summary
      print_summary(results)
    else
      {:error, reason} ->
        IO.puts("Configuration error: #{reason}")
        System.halt(1)
    end
  end

  defp load_supabase_config do
    supabase_url = System.get_env("SUPABASE_URL")
    access_key = System.get_env("SUPABASE_S3_ACCESS_KEY_ID")
    secret_key = System.get_env("SUPABASE_S3_SECRET_ACCESS_KEY")

    cond do
      is_nil(supabase_url) or supabase_url == "" ->
        {:error, "SUPABASE_URL not set"}

      is_nil(access_key) or access_key == "" ->
        {:error, "SUPABASE_S3_ACCESS_KEY_ID not set"}

      is_nil(secret_key) or secret_key == "" ->
        {:error, "SUPABASE_S3_SECRET_ACCESS_KEY not set"}

      true ->
        # Extract project ref from URL
        project_ref =
          supabase_url
          |> String.replace(~r/^https?:\/\//, "")
          |> String.split(".")
          |> List.first()

        config = [
          access_key_id: access_key,
          secret_access_key: secret_key,
          region: "eu-central-1",
          scheme: "https://",
          host: "#{project_ref}.supabase.co/storage/v1/s3",
          port: 443
        ]

        IO.puts("Supabase S3 endpoint: #{project_ref}.supabase.co/storage/v1/s3")
        {:ok, config}
    end
  end

  defp load_r2_config do
    account_id = System.get_env("CLOUDFLARE_ACCOUNT_ID")
    access_key = System.get_env("CLOUDFLARE_ACCESS_KEY_ID")
    secret_key = System.get_env("CLOUDFLARE_SECRET_ACCESS_KEY")

    cond do
      is_nil(account_id) or account_id == "" ->
        {:error, "CLOUDFLARE_ACCOUNT_ID not set"}

      is_nil(access_key) or access_key == "" ->
        {:error, "CLOUDFLARE_ACCESS_KEY_ID not set"}

      is_nil(secret_key) or secret_key == "" ->
        {:error, "CLOUDFLARE_SECRET_ACCESS_KEY not set"}

      true ->
        config = [
          access_key_id: access_key,
          secret_access_key: secret_key,
          region: "auto",
          scheme: "https://",
          host: "#{account_id}.r2.cloudflarestorage.com",
          port: 443
        ]

        IO.puts("R2 endpoint: #{account_id}.r2.cloudflarestorage.com\n")
        {:ok, config}
    end
  end

  defp migrate_folder(folder, supabase_config, r2_config, dry_run) do
    IO.puts("--- Migrating folder: #{folder} ---")

    case list_supabase_files(folder, supabase_config) do
      {:ok, files} ->
        IO.puts("  Found #{length(files)} files")

        if length(files) == 0 do
          %{folder: folder, success: 0, failed: 0, skipped: 0, files: []}
        else
          results =
            files
            |> Enum.map(fn file ->
              migrate_file(file, supabase_config, r2_config, dry_run)
            end)

          success = Enum.count(results, fn {status, _} -> status == :ok end)
          failed = Enum.count(results, fn {status, _} -> status == :error end)
          skipped = Enum.count(results, fn {status, _} -> status == :skipped end)

          IO.puts("  Completed: #{success} success, #{failed} failed, #{skipped} skipped\n")

          %{folder: folder, success: success, failed: failed, skipped: skipped, files: results}
        end

      {:error, reason} ->
        IO.puts("  ERROR listing files: #{inspect(reason)}\n")
        %{folder: folder, success: 0, failed: 0, skipped: 0, error: reason, files: []}
    end
  end

  defp list_supabase_files(folder, config) do
    list_supabase_files_with_retry(folder, config, 0)
  end

  defp list_supabase_files_with_retry(folder, config, attempt) do
    # List all objects in the folder
    case ExAws.S3.list_objects(@supabase_bucket, prefix: "#{folder}/")
         |> ExAws.request(config) do
      {:ok, %{body: %{contents: contents}}} ->
        files =
          contents
          |> Enum.filter(fn obj ->
            # Filter out folder markers (keys ending with /)
            !String.ends_with?(obj.key, "/")
          end)
          |> Enum.map(fn obj ->
            %{
              key: obj.key,
              size: String.to_integer(obj.size),
              last_modified: obj.last_modified
            }
          end)

        {:ok, files}

      {:ok, %{body: body}} ->
        # Empty folder or different response format
        {:ok, Map.get(body, :contents, []) |> Enum.map(fn obj -> %{key: obj.key, size: 0} end)}

      {:error, {:http_error, 429, _}} when attempt < @max_retries ->
        delay = @base_delay_ms * :math.pow(2, attempt) |> round()
        IO.puts("    Rate limited, waiting #{delay}ms before retry #{attempt + 1}/#{@max_retries}...")
        Process.sleep(delay)
        list_supabase_files_with_retry(folder, config, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp migrate_file(file, supabase_config, r2_config, dry_run) do
    key = file.key
    size_kb = Float.round(file.size / 1024, 1)

    if dry_run do
      IO.puts("    [DRY RUN] Would migrate: #{key} (#{size_kb} KB)")
      {:skipped, key}
    else
      IO.write("    Migrating: #{key} (#{size_kb} KB)... ")

      # Download from Supabase
      case download_from_supabase(key, supabase_config) do
        {:ok, data} ->
          # Upload to R2
          case upload_to_r2(key, data, r2_config) do
            {:ok, _} ->
              IO.puts("OK")
              {:ok, key}

            {:error, reason} ->
              IO.puts("FAILED (upload): #{inspect(reason)}")
              {:error, {key, reason}}
          end

        {:error, reason} ->
          IO.puts("FAILED (download): #{inspect(reason)}")
          {:error, {key, reason}}
      end
    end
  end

  defp download_from_supabase(key, config) do
    download_from_supabase_with_retry(key, config, 0)
  end

  defp download_from_supabase_with_retry(key, config, attempt) do
    case ExAws.S3.get_object(@supabase_bucket, key) |> ExAws.request(config) do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, {:http_error, 429, _}} when attempt < @max_retries ->
        delay = @base_delay_ms * :math.pow(2, attempt) |> round()
        IO.write("(rate limited, retry #{attempt + 1})... ")
        Process.sleep(delay)
        download_from_supabase_with_retry(key, config, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upload_to_r2(key, data, config) do
    content_type = get_content_type(key)

    case ExAws.S3.put_object(@r2_bucket, key, data, content_type: content_type)
         |> ExAws.request(config) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_content_type(filename) do
    cond do
      String.ends_with?(filename, ".xml.gz") -> "application/gzip"
      String.ends_with?(filename, ".xml") -> "application/xml"
      String.ends_with?(filename, ".txt") -> "text/plain"
      String.ends_with?(filename, ".jpg") or String.ends_with?(filename, ".jpeg") -> "image/jpeg"
      String.ends_with?(filename, ".png") -> "image/png"
      String.ends_with?(filename, ".gif") -> "image/gif"
      String.ends_with?(filename, ".webp") -> "image/webp"
      String.ends_with?(filename, ".svg") -> "image/svg+xml"
      true -> "application/octet-stream"
    end
  end

  defp print_summary(results) do
    IO.puts("\n=== Migration Summary ===\n")

    total_success = Enum.sum(Enum.map(results, & &1.success))
    total_failed = Enum.sum(Enum.map(results, & &1.failed))
    total_skipped = Enum.sum(Enum.map(results, & &1.skipped))

    Enum.each(results, fn result ->
      status =
        cond do
          Map.has_key?(result, :error) -> "ERROR"
          result.failed > 0 -> "PARTIAL"
          result.success > 0 -> "OK"
          true -> "EMPTY"
        end

      IO.puts("  #{result.folder}: #{status} (#{result.success} migrated, #{result.failed} failed)")
    end)

    IO.puts("\nTotal: #{total_success} migrated, #{total_failed} failed, #{total_skipped} skipped")

    if total_success > 0 do
      IO.puts("\nFiles are now available at: #{@cdn_url}/<path>")
      IO.puts("Example: #{@cdn_url}/events/your-file.jpg")
    end

    IO.puts("\n=== Done ===\n")
  end
end

# Parse command line arguments
args = System.argv()
dry_run = "--dry-run" in args

folder =
  case Enum.find_index(args, &(&1 == "--folder")) do
    nil -> nil
    idx -> Enum.at(args, idx + 1)
  end

# Run migration
SupabaseToR2Migration.run(dry_run: dry_run, folder: folder)
