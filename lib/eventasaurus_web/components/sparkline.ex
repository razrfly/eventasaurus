defmodule EventasaurusWeb.Components.Sparkline do
  @moduledoc """
  Server-side SVG sparkline generation.

  Generates compact sparkline visualizations for trend data in the monitoring dashboard.
  Each sparkline shows success rate over time (7 days by default). The SVG is generated
  manually with path elements for the line and gradient fill area.

  ## Usage

      alias EventasaurusWeb.Components.Sparkline

      # Generate sparkline SVG from trend data
      svg = Sparkline.render(trend_data.data_points)

      # With custom dimensions
      svg = Sparkline.render(trend_data.data_points, width: 100, height: 24)
  """

  @typedoc "Data point with success rate for sparkline rendering"
  @type data_point :: %{success_rate: float()} | map()

  @typedoc "Trend direction for arrow indicator"
  @type trend_direction :: :improving | :stable | :degrading

  @default_width 80
  @default_height 20

  @doc """
  Renders a sparkline SVG from data points.

  ## Parameters

  - `data_points` - List of maps with `:success_rate` keys (0-100 scale)
  - `opts` - Options:
    - `:width` - SVG width in pixels (default: 80)
    - `:height` - SVG height in pixels (default: 20)
    - `:color` - Line/fill color (default: based on average success rate)

  ## Returns

  An SVG string that can be rendered directly in templates.

  ## Examples

      iex> Sparkline.render([%{success_rate: 95.0}, %{success_rate: 97.0}, %{success_rate: 96.0}])
      "<svg ...>...</svg>"
  """
  @spec render([data_point()] | any(), keyword()) :: String.t()
  def render(data_points, opts \\ [])

  def render([], _opts), do: empty_sparkline()

  def render(data_points, opts) when is_list(data_points) do
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)
    # Generate unique ID for this sparkline instance to avoid duplicate ID warnings
    unique_id = Keyword.get(opts, :id, generate_unique_id())

    # Extract success rates, defaulting to 100 for missing data
    values =
      data_points
      |> Enum.map(fn point ->
        Map.get(point, :success_rate, 100.0)
      end)

    # Determine color based on average success rate
    avg_rate = Enum.sum(values) / length(values)
    color = Keyword.get(opts, :color, color_for_rate(avg_rate))

    # Build the sparkline SVG
    build_sparkline_svg(values, width, height, color, unique_id)
  end

  def render(_, _opts), do: empty_sparkline()

  @doc """
  Renders a trend indicator arrow based on trend direction.

  ## Parameters

  - `direction` - One of `:improving`, `:stable`, or `:degrading`

  ## Returns

  An HTML string with the appropriate arrow and color.
  """
  @spec trend_arrow(trend_direction() | any()) :: String.t()
  def trend_arrow(:improving) do
    ~s(<span class="text-green-500 dark:text-green-400 font-bold" title="Improving">↑</span>)
  end

  def trend_arrow(:degrading) do
    ~s(<span class="text-red-500 dark:text-red-400 font-bold" title="Degrading">↓</span>)
  end

  def trend_arrow(:stable) do
    ~s(<span class="text-gray-400 dark:text-gray-500" title="Stable">→</span>)
  end

  def trend_arrow(_), do: trend_arrow(:stable)

  # Private helpers

  defp empty_sparkline do
    ~s(<svg width="80" height="20" class="text-gray-300">
      <text x="40" y="14" text-anchor="middle" font-size="10" fill="currentColor">--</text>
    </svg>)
  end

  # green-500
  defp color_for_rate(rate) when rate >= 95, do: "#22c55e"
  # yellow-500
  defp color_for_rate(rate) when rate >= 80, do: "#eab308"
  # red-500
  defp color_for_rate(_rate), do: "#ef4444"

  defp build_sparkline_svg(values, width, height, color, unique_id) do
    n = length(values)

    if n < 2 do
      # Not enough data for a line, show a dot
      single_value_svg(List.first(values, 100.0), width, height, color)
    else
      # Normalize values to fit in SVG height with padding
      padding = 2
      usable_height = height - 2 * padding

      # Find min/max for scaling (keep 0-100 range for consistency)
      min_val = 0
      max_val = 100
      range = max_val - min_val

      # Calculate points
      points =
        values
        |> Enum.with_index()
        |> Enum.map(fn {val, i} ->
          x = i * (width - 1) / (n - 1)
          # Invert Y because SVG Y grows downward
          normalized = (val - min_val) / range
          y = height - padding - normalized * usable_height
          {x, y}
        end)

      # Build path
      path_d = build_path(points)

      # Build filled area (for gradient effect)
      area_d = build_area_path(points, width, height)

      # Use unique gradient ID to avoid duplicate ID warnings in DOM
      gradient_id = "sparkline-gradient-#{unique_id}"

      """
      <svg width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" class="sparkline">
        <defs>
          <linearGradient id="#{gradient_id}" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style="stop-color:#{color};stop-opacity:0.3" />
            <stop offset="100%" style="stop-color:#{color};stop-opacity:0.05" />
          </linearGradient>
        </defs>
        <path d="#{area_d}" fill="url(##{gradient_id})" />
        <path d="#{path_d}" fill="none" stroke="#{color}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
      """
    end
  end

  defp single_value_svg(value, width, height, color) do
    # Show a horizontal line at the value's position
    padding = 2
    usable_height = height - 2 * padding
    normalized = value / 100
    y = height - padding - normalized * usable_height

    """
    <svg width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" class="sparkline">
      <line x1="0" y1="#{y}" x2="#{width}" y2="#{y}" stroke="#{color}" stroke-width="1.5" stroke-dasharray="2,2" />
    </svg>
    """
  end

  defp build_path(points) do
    [{x0, y0} | rest] = points

    initial = "M#{format_coord(x0)},#{format_coord(y0)}"

    rest
    |> Enum.reduce(initial, fn {x, y}, acc ->
      acc <> " L#{format_coord(x)},#{format_coord(y)}"
    end)
  end

  defp build_area_path(points, _width, height) do
    [{x0, y0} | rest] = points
    {xn, _yn} = List.last(points)

    # Start at first point, draw line through all points,
    # then down to bottom, across to start, and back up
    initial = "M#{format_coord(x0)},#{format_coord(y0)}"

    line_path =
      rest
      |> Enum.reduce(initial, fn {x, y}, acc ->
        acc <> " L#{format_coord(x)},#{format_coord(y)}"
      end)

    # Close the area: down to bottom-right, across to bottom-left, up to start
    line_path <>
      " L#{format_coord(xn)},#{height}" <>
      " L#{format_coord(x0)},#{height}" <>
      " Z"
  end

  defp format_coord(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_coord(n), do: to_string(n)

  # Generate a unique ID for each sparkline instance
  defp generate_unique_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
