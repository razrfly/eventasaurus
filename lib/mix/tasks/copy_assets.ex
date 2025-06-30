defmodule Mix.Tasks.CopyAssets do
  @moduledoc """
  Copies theme CSS files from assets/ to priv/static/ for development hot reloading.

  This task ensures that theme CSS files are properly served in development
  without requiring manual copying or asset compilation.
  """
  use Mix.Task

  @shortdoc "Copies theme CSS assets to static directory"

  def run(_args) do
    copy_theme_css()
  end

  @doc """
  Copies all theme CSS files from assets/css/themes/ to priv/static/themes/
  """
  def copy_theme_css do
    source_dir = "assets/css/themes"
    dest_dir = "priv/static/themes"

    # Ensure destination directory exists
    File.mkdir_p!(dest_dir)

    # Copy all CSS files
    case File.ls(source_dir) do
      {:ok, files} ->
        css_files = Enum.filter(files, &String.ends_with?(&1, ".css"))

        Enum.each(css_files, fn file ->
          source = Path.join(source_dir, file)
          dest = Path.join(dest_dir, file)

          case File.cp(source, dest) do
            :ok ->
              Mix.shell().info("Copied #{source} -> #{dest}")
            {:error, reason} ->
              Mix.shell().error("Failed to copy #{file}: #{reason}")
          end
        end)

        Mix.shell().info("✅ Theme CSS files copied successfully!")

      {:error, reason} ->
        Mix.shell().error("Failed to read source directory #{source_dir}: #{reason}")
    end
  end

  @doc """
  Watches for changes in theme CSS files and automatically copies them.
  This is used by the development file watcher.
  """
  def watch_and_copy do
    copy_theme_css()

    # Set up a simple polling watcher since we can't rely on inotify on all systems
    spawn(fn ->
      watch_loop()
    end)
  end

  defp watch_loop do
    Process.sleep(1000) # Check every second
    copy_theme_css()
    watch_loop()
  end
end
