defmodule EventasaurusWeb.Admin.MlBacktestsLive do
  @moduledoc """
  Admin interface for ML category classification backtests.
  Displays backtest runs, results, and confusion matrices for model validation.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Categories.CategoryBacktester

  @impl true
  def mount(_params, _session, socket) do
    runs = CategoryBacktester.list_runs(limit: 50)

    socket =
      socket
      |> assign(:page_title, "ML Backtests")
      |> assign(:runs, runs)
      |> assign(:selected_run, nil)
      |> assign(:results, [])
      |> assign(:confusion_matrix, nil)
      |> assign(:filter_incorrect, false)
      |> assign(:results_limit, 50)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    run_id = String.to_integer(id)

    case CategoryBacktester.get_run(run_id) do
      {:ok, run} ->
        {:ok, results} =
          CategoryBacktester.get_results(run.id,
            only_incorrect: socket.assigns.filter_incorrect,
            limit: socket.assigns.results_limit
          )

        {:ok, matrix} = CategoryBacktester.confusion_matrix(run.id)

        socket =
          socket
          |> assign(:selected_run, run)
          |> assign(:results, results)
          |> assign(:confusion_matrix, matrix)
          |> assign(:page_title, "Backtest: #{run.name}")

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Backtest run not found")
         |> push_navigate(to: ~p"/admin/ml/backtests")}
    end
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:selected_run, nil)
      |> assign(:results, [])
      |> assign(:confusion_matrix, nil)
      |> assign(:page_title, "ML Backtests")

    {:noreply, socket}
  end

  @impl true
  def handle_event("view_run", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/ml/backtests/#{id}")}
  end

  @impl true
  def handle_event("back_to_list", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/ml/backtests")}
  end

  @impl true
  def handle_event("toggle_incorrect", _params, socket) do
    filter_incorrect = !socket.assigns.filter_incorrect

    if socket.assigns.selected_run do
      {:ok, results} =
        CategoryBacktester.get_results(socket.assigns.selected_run.id,
          only_incorrect: filter_incorrect,
          limit: socket.assigns.results_limit
        )

      {:noreply,
       socket
       |> assign(:filter_incorrect, filter_incorrect)
       |> assign(:results, results)}
    else
      {:noreply, assign(socket, :filter_incorrect, filter_incorrect)}
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    new_limit = socket.assigns.results_limit + 50

    if socket.assigns.selected_run do
      {:ok, results} =
        CategoryBacktester.get_results(socket.assigns.selected_run.id,
          only_incorrect: socket.assigns.filter_incorrect,
          limit: new_limit
        )

      {:noreply,
       socket
       |> assign(:results_limit, new_limit)
       |> assign(:results, results)}
    else
      {:noreply, assign(socket, :results_limit, new_limit)}
    end
  end

  # Helper functions for the template

  def format_accuracy(nil), do: "-"
  def format_accuracy(value), do: "#{Float.round(value * 100, 1)}%"

  def format_f1(nil), do: "-"
  def format_f1(value), do: Float.round(value, 3)

  def format_score(nil), do: "-"
  def format_score(value), do: Float.round(value, 2)

  def format_datetime(nil), do: "-"

  def format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  def status_color("completed"), do: "bg-green-100 text-green-800"
  def status_color("failed"), do: "bg-red-100 text-red-800"
  def status_color("running"), do: "bg-yellow-100 text-yellow-800"
  def status_color(_), do: "bg-gray-100 text-gray-800"

  def correct_indicator(true), do: {"text-green-600", "✓"}
  def correct_indicator(false), do: {"text-red-600", "✗"}

  def confusion_matrix_categories(matrix) when is_map(matrix) do
    matrix
    |> Map.keys()
    |> Enum.flat_map(fn {expected, predicted} -> [expected, predicted] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def confusion_matrix_categories(_), do: []

  def matrix_cell_value(matrix, expected, predicted) do
    Map.get(matrix, {expected, predicted}, 0)
  end

  def matrix_cell_color(count, max_count) when max_count > 0 do
    intensity = count / max_count
    # Scale from white to blue
    cond do
      intensity > 0.8 -> "bg-blue-600 text-white"
      intensity > 0.6 -> "bg-blue-500 text-white"
      intensity > 0.4 -> "bg-blue-400 text-white"
      intensity > 0.2 -> "bg-blue-300"
      intensity > 0 -> "bg-blue-100"
      true -> "bg-gray-50"
    end
  end

  def matrix_cell_color(_, _), do: "bg-gray-50"

  def diagonal_cell?(expected, predicted), do: expected == predicted
end
