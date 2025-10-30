defmodule EventasaurusWeb.Admin.SitemapLive do
  use EventasaurusWeb, :live_view

  alias Eventasaurus.SitemapStats

  @impl true
  def mount(_params, _session, socket) do
    socket = assign_defaults(socket)

    if connected?(socket) do
      {:ok, load_stats(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_stats(socket)}
  end

  @impl true
  def handle_event("generate_sitemap", _params, socket) do
    # Queue the sitemap generation worker via Oban
    case Eventasaurus.Workers.SitemapWorker.new(%{}) |> Oban.insert() do
      {:ok, job} ->
        socket =
          socket
          |> put_flash(
            :info,
            "✅ Queued sitemap generation job ##{job.id}. This will take a few minutes."
          )
          |> assign(:generating, true)

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to queue sitemap generation")}
    end
  end

  defp load_stats(socket) do
    stats = SitemapStats.expected_counts()
    samples = SitemapStats.sample_urls()

    socket
    |> assign(:stats, stats)
    |> assign(:samples, samples)
    |> assign(:last_updated, DateTime.utc_now())
    |> assign(:generating, false)
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:page_title, "Sitemap Statistics")
    |> assign(:stats, nil)
    |> assign(:samples, nil)
    |> assign(:last_updated, nil)
    |> assign(:generating, false)
  end

  defp format_number(nil), do: "0"

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map_join(",", &Enum.join(&1, ""))
  end

  defp format_number(_), do: "0"

  defp status_icon(count) when is_integer(count) and count > 0, do: "✅"
  defp status_icon(_), do: "⚠️"
end
