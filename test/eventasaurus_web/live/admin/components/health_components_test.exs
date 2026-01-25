defmodule EventasaurusWeb.Admin.Components.HealthComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EventasaurusWeb.Admin.Components.HealthComponents

  describe "health_score_pill/1" do
    test "renders healthy status correctly" do
      assigns = %{score: 85, status: :healthy}
      html = render_component(&HealthComponents.health_score_pill/1, assigns)

      assert html =~ "85%"
      assert html =~ "bg-green-100"
      assert html =~ "text-green-800"
    end

    test "renders warning status correctly" do
      assigns = %{score: 65, status: :warning}
      html = render_component(&HealthComponents.health_score_pill/1, assigns)

      assert html =~ "65%"
      assert html =~ "bg-yellow-100"
      assert html =~ "text-yellow-800"
    end

    test "renders critical status correctly" do
      assigns = %{score: 35, status: :critical}
      html = render_component(&HealthComponents.health_score_pill/1, assigns)

      assert html =~ "35%"
      assert html =~ "bg-red-100"
      assert html =~ "text-red-800"
    end

    test "renders disabled status correctly" do
      assigns = %{score: 0, status: :disabled}
      html = render_component(&HealthComponents.health_score_pill/1, assigns)

      assert html =~ "0%"
      assert html =~ "bg-gray-100"
      assert html =~ "text-gray-800"
    end

    test "hides score when show_score is false" do
      assigns = %{score: 75, status: :healthy, show_score: false}
      html = render_component(&HealthComponents.health_score_pill/1, assigns)

      refute html =~ "75%"
      assert html =~ "Healthy"
    end
  end

  describe "health_score_large/1" do
    test "renders large score with SVG progress ring" do
      assigns = %{score: 75, status: :warning}
      html = render_component(&HealthComponents.health_score_large/1, assigns)

      assert html =~ "75"
      assert html =~ "<svg"
      assert html =~ "text-yellow-500"
    end

    test "renders healthy status with green ring" do
      assigns = %{score: 90, status: :healthy}
      html = render_component(&HealthComponents.health_score_large/1, assigns)

      assert html =~ "text-green-500"
      assert html =~ "text-green-600"
    end

    test "renders critical status with red ring" do
      assigns = %{score: 30, status: :critical}
      html = render_component(&HealthComponents.health_score_large/1, assigns)

      assert html =~ "text-red-500"
      assert html =~ "text-red-600"
    end

    test "renders label when provided" do
      assigns = %{score: 80, status: :healthy, label: "City Health"}
      html = render_component(&HealthComponents.health_score_large/1, assigns)

      assert html =~ "City Health"
    end
  end

  describe "progress_bar/1" do
    test "renders with default values" do
      assigns = %{value: 50}
      html = render_component(&HealthComponents.progress_bar/1, assigns)

      assert html =~ "width: 50%"
      assert html =~ "bg-blue-500"
      assert html =~ "h-2"
    end

    test "renders with custom color" do
      assigns = %{value: 75, color: :green}
      html = render_component(&HealthComponents.progress_bar/1, assigns)

      assert html =~ "bg-green-500"
    end

    test "renders with large size" do
      assigns = %{value: 60, size: :lg}
      html = render_component(&HealthComponents.progress_bar/1, assigns)

      assert html =~ "h-3"
    end

    test "renders with small size" do
      assigns = %{value: 40, size: :sm}
      html = render_component(&HealthComponents.progress_bar/1, assigns)

      assert html =~ "h-1.5"
    end

    test "caps value at 100" do
      assigns = %{value: 150}
      html = render_component(&HealthComponents.progress_bar/1, assigns)

      assert html =~ "width: 100%"
    end

    test "shows percentage when show_label is true" do
      assigns = %{value: 80, show_label: true}
      html = render_component(&HealthComponents.progress_bar/1, assigns)

      assert html =~ "80%"
    end
  end

  describe "sparkline/1" do
    test "renders sparkline bars from data" do
      assigns = %{data: [10, 20, 30, 40, 50, 60, 70]}
      html = render_component(&HealthComponents.sparkline/1, assigns)

      # Should have bars with bg-blue-500 for last one and bg-gray-300 for others
      assert html =~ "bg-blue-500"
      assert html =~ "bg-gray-300"
    end

    test "handles empty data gracefully" do
      assigns = %{data: []}
      html = render_component(&HealthComponents.sparkline/1, assigns)

      # Should still render the container
      assert html =~ "flex items-end"
    end

    test "handles all zeros with minimum height" do
      assigns = %{data: [0, 0, 0, 0, 0, 0, 0]}
      html = render_component(&HealthComponents.sparkline/1, assigns)

      # Should render with minimum 1px heights
      assert html =~ "height: 1px"
    end

    test "shows title with data values" do
      assigns = %{data: [1, 2, 3, 4, 5, 6, 7]}
      html = render_component(&HealthComponents.sparkline/1, assigns)

      assert html =~ "title="
      assert html =~ "1, 2, 3, 4, 5, 6, 7"
    end
  end

  describe "stat_card/1" do
    test "renders card with title, value, and icon" do
      assigns = %{title: "Total Events", value: 1234, icon: "📊", color: :blue}
      html = render_component(&HealthComponents.stat_card/1, assigns)

      assert html =~ "Total Events"
      assert html =~ "1234"
      assert html =~ "📊"
      assert html =~ "border-blue-500"
    end

    test "renders with different colors" do
      for color <- [:blue, :green, :yellow, :red, :purple, :gray] do
        assigns = %{title: "Test", value: 100, icon: "🔵", color: color}
        html = render_component(&HealthComponents.stat_card/1, assigns)

        assert html =~ "border-#{color}-"
      end
    end

    test "renders subtitle when provided" do
      assigns = %{title: "Sources", value: 8, icon: "🔌", color: :purple, subtitle: "3 healthy"}
      html = render_component(&HealthComponents.stat_card/1, assigns)

      assert html =~ "3 healthy"
    end
  end

  describe "admin_stat_card/1" do
    test "renders card with title, value, and SVG icon" do
      assigns = %{title: "Total Events", value: 1234, icon_type: :chart, color: :blue}
      html = render_component(&HealthComponents.admin_stat_card/1, assigns)

      assert html =~ "Total Events"
      assert html =~ "1234"
      assert html =~ "<svg"
      assert html =~ "border-blue-500"
      assert html =~ "bg-blue-100"
    end

    test "renders title as label above value" do
      assigns = %{title: "Active Sources", value: 8, icon_type: :plug, color: :purple}
      html = render_component(&HealthComponents.admin_stat_card/1, assigns)

      # Title should have text-sm styling (label pattern)
      assert html =~ "text-sm font-medium text-gray-500"
      # Value should have text-3xl styling (large number pattern)
      assert html =~ "text-3xl font-bold"
    end

    test "renders with different colors" do
      for color <- [:blue, :green, :yellow, :red, :purple, :indigo] do
        assigns = %{title: "Test", value: 100, icon_type: :chart, color: color}
        html = render_component(&HealthComponents.admin_stat_card/1, assigns)

        assert html =~ "border-#{color}-500"
        assert html =~ "bg-#{color}-100"
      end
    end

    test "renders with different icon types" do
      for icon_type <- [:chart, :plug, :location, :tag, :calendar, :users] do
        assigns = %{title: "Test", value: 42, icon_type: icon_type, color: :blue}
        html = render_component(&HealthComponents.admin_stat_card/1, assigns)

        assert html =~ "<svg"
        assert html =~ "w-12 h-12 rounded-full"
      end
    end

    test "renders subtitle when provided" do
      assigns = %{title: "Sources", value: 8, icon_type: :plug, color: :purple, subtitle: "3 healthy"}
      html = render_component(&HealthComponents.admin_stat_card/1, assigns)

      assert html =~ "3 healthy"
    end

    test "icon appears in circular background on right side" do
      assigns = %{title: "Events", value: 100, icon_type: :chart, color: :blue}
      html = render_component(&HealthComponents.admin_stat_card/1, assigns)

      # Icon should be in a circular div
      assert html =~ "w-12 h-12 rounded-full"
      # Layout should use flex justify-between
      assert html =~ "flex items-center justify-between"
    end
  end

  describe "admin_icon/1" do
    test "renders chart icon" do
      assigns = %{type: :chart, class: "w-6 h-6"}
      html = render_component(&HealthComponents.admin_icon/1, assigns)

      assert html =~ "<svg"
      assert html =~ "w-6 h-6"
    end

    test "renders plug icon" do
      assigns = %{type: :plug, class: "w-6 h-6 text-purple-600"}
      html = render_component(&HealthComponents.admin_icon/1, assigns)

      assert html =~ "<svg"
      assert html =~ "text-purple-600"
    end

    test "renders location icon" do
      assigns = %{type: :location, class: "w-6 h-6"}
      html = render_component(&HealthComponents.admin_icon/1, assigns)

      assert html =~ "<svg"
      # Location icon has two paths
      assert html =~ "path"
    end

    test "renders fallback icon for unknown types" do
      assigns = %{type: :unknown, class: "w-6 h-6"}
      html = render_component(&HealthComponents.admin_icon/1, assigns)

      assert html =~ "<svg"
    end
  end

  describe "health_metric_card/1" do
    test "renders card with label, value, and weight" do
      assigns = %{label: "Event Coverage", value: 85, weight: "40%", color: :blue}
      html = render_component(&HealthComponents.health_metric_card/1, assigns)

      assert html =~ "Event Coverage"
      assert html =~ "85%"
      assert html =~ "40%"
    end

    test "renders with progress bar" do
      assigns = %{label: "Test", value: 75, weight: "30%", color: :green}
      html = render_component(&HealthComponents.health_metric_card/1, assigns)

      assert html =~ "bg-green-500"
      assert html =~ "width: 75%"
    end

    test "renders description when provided" do
      assigns = %{label: "Event Coverage", value: 85, weight: "40%", color: :blue, description: "7-day availability"}
      html = render_component(&HealthComponents.health_metric_card/1, assigns)

      assert html =~ "7-day availability"
    end

    test "shows on target indicator when value meets target" do
      assigns = %{label: "Test", value: 90, weight: "30%", color: :green, target: 80}
      html = render_component(&HealthComponents.health_metric_card/1, assigns)

      assert html =~ "On target"
      assert html =~ "text-green-600"
    end

    test "shows below indicator when value is below target" do
      assigns = %{label: "Test", value: 60, weight: "30%", color: :red, target: 80}
      html = render_component(&HealthComponents.health_metric_card/1, assigns)

      assert html =~ "Below"
      assert html =~ "text-red-600"
    end

    test "shows target value" do
      assigns = %{label: "Test", value: 70, weight: "30%", color: :yellow, target: 80}
      html = render_component(&HealthComponents.health_metric_card/1, assigns)

      assert html =~ "Target: 80%"
    end

    test "does not show target indicator when no target provided" do
      assigns = %{label: "Test", value: 70, weight: "30%", color: :blue}
      html = render_component(&HealthComponents.health_metric_card/1, assigns)

      refute html =~ "Target:"
      refute html =~ "On target"
      refute html =~ "Below"
    end

    test "renders with different colors" do
      for color <- [:blue, :green, :yellow, :red, :purple] do
        assigns = %{label: "Test", value: 50, weight: "20%", color: color}
        html = render_component(&HealthComponents.health_metric_card/1, assigns)

        assert html =~ "bg-#{color}-500"
      end
    end

    test "caps progress bar at 100%" do
      assigns = %{label: "Test", value: 150, weight: "30%", color: :blue}
      html = render_component(&HealthComponents.health_metric_card/1, assigns)

      assert html =~ "width: 100%"
    end
  end

  describe "health_component_bar/1" do
    test "renders component bar with label, value, and weight" do
      assigns = %{label: "Event Coverage", value: 85, weight: "40%", color: :blue}
      html = render_component(&HealthComponents.health_component_bar/1, assigns)

      assert html =~ "Event Coverage"
      assert html =~ "85%"
      assert html =~ "Weight: 40%"
      assert html =~ "bg-blue-500"
    end

    test "renders with target indicator when provided" do
      assigns = %{label: "Test", value: 70, weight: "30%", color: :green, target: 80}
      html = render_component(&HealthComponents.health_component_bar/1, assigns)

      assert html =~ "Target: 80%"
    end

    test "renders without target when not provided" do
      assigns = %{label: "Test", value: 70, weight: "30%", color: :green}
      html = render_component(&HealthComponents.health_component_bar/1, assigns)

      refute html =~ "Target:"
    end

    test "shows status indicator when show_status is true and target provided" do
      assigns = %{label: "Test", value: 90, weight: "30%", color: :green, target: 80, show_status: true}
      html = render_component(&HealthComponents.health_component_bar/1, assigns)

      assert html =~ "✓"
    end

    test "renders description when provided" do
      assigns = %{label: "Event Coverage", value: 85, weight: "40%", color: :blue, description: "7-day event availability"}
      html = render_component(&HealthComponents.health_component_bar/1, assigns)

      assert html =~ "7-day event availability"
    end

    test "renders without description when not provided" do
      assigns = %{label: "Test", value: 70, weight: "30%", color: :green}
      html = render_component(&HealthComponents.health_component_bar/1, assigns)

      # Should not have a description paragraph
      refute html =~ "text-gray-400 mt-0.5"
    end
  end

  describe "trend_indicator/1" do
    test "renders positive trend with up arrow" do
      assigns = %{change: 15}
      html = render_component(&HealthComponents.trend_indicator/1, assigns)

      assert html =~ "↑"
      assert html =~ "+15%"
      assert html =~ "text-green-600"
    end

    test "renders negative trend with down arrow" do
      assigns = %{change: -10}
      html = render_component(&HealthComponents.trend_indicator/1, assigns)

      assert html =~ "↓"
      assert html =~ "-10%"
      assert html =~ "text-red-600"
    end

    test "renders zero change with right arrow" do
      assigns = %{change: 0}
      html = render_component(&HealthComponents.trend_indicator/1, assigns)

      assert html =~ "→"
      assert html =~ "0%"
      assert html =~ "text-gray-500"
    end

    test "renders with small size" do
      assigns = %{change: 5, size: :sm}
      html = render_component(&HealthComponents.trend_indicator/1, assigns)

      assert html =~ "text-xs"
    end

    test "hides arrow when show_arrow is false" do
      assigns = %{change: 10, show_arrow: false}
      html = render_component(&HealthComponents.trend_indicator/1, assigns)

      refute html =~ "↑"
      assert html =~ "+10%"
    end
  end

  describe "status_badge/1" do
    test "renders failure badge" do
      assigns = %{state: "failure"}
      html = render_component(&HealthComponents.status_badge/1, assigns)

      assert html =~ "✗"
      assert html =~ "Failed"
      assert html =~ "bg-red-100"
    end

    test "renders cancelled badge with orange styling" do
      assigns = %{state: "cancelled"}
      html = render_component(&HealthComponents.status_badge/1, assigns)

      assert html =~ "Cancelled"
      assert html =~ "bg-orange-100"
    end

    test "renders discarded badge" do
      assigns = %{state: "discarded"}
      html = render_component(&HealthComponents.status_badge/1, assigns)

      assert html =~ "Discarded"
      assert html =~ "bg-gray-100"
    end

    test "renders success badge" do
      assigns = %{state: "success"}
      html = render_component(&HealthComponents.status_badge/1, assigns)

      assert html =~ "✓"
      assert html =~ "Success"
      assert html =~ "bg-green-100"
    end

    test "handles unknown states with capitalized label" do
      assigns = %{state: "pending"}
      html = render_component(&HealthComponents.status_badge/1, assigns)

      assert html =~ "Pending"
    end
  end

  describe "helper functions" do
    test "status_indicator/1 returns correct emoji and classes" do
      assert HealthComponents.status_indicator(:healthy) == {"🟢", "Healthy", "text-green-600"}
      assert HealthComponents.status_indicator(:warning) == {"🟡", "Warning", "text-yellow-600"}
      assert HealthComponents.status_indicator(:critical) == {"🔴", "Critical", "text-red-600"}
      assert HealthComponents.status_indicator(:disabled) == {"⚪", "Disabled", "text-gray-400"}
      assert HealthComponents.status_indicator(:unknown) == {"⚫", "Unknown", "text-gray-500"}
    end

    test "status_classes/1 returns correct CSS classes" do
      assert HealthComponents.status_classes(:healthy) =~ "bg-green-100"
      assert HealthComponents.status_classes(:warning) =~ "bg-yellow-100"
      assert HealthComponents.status_classes(:critical) =~ "bg-red-100"
      assert HealthComponents.status_classes(:disabled) =~ "bg-gray-100"
    end

    test "sparkline_heights/1 normalizes data to percentages" do
      data = [10, 20, 30, 40, 50]
      heights = HealthComponents.sparkline_heights(data)

      assert length(heights) == 5
      # Max value (50) should be 100%
      assert List.last(heights) == 100
      # First value (10) should be 20%
      assert List.first(heights) == 20
    end

    test "sparkline_heights/1 handles zeros" do
      data = [0, 0, 0]
      heights = HealthComponents.sparkline_heights(data)

      assert heights == [0, 0, 0]
    end

    test "sparkline_heights/1 handles nil" do
      heights = HealthComponents.sparkline_heights(nil)

      assert heights == List.duplicate(0, 7)
    end

    test "sparkline_heights/1 ensures minimum height for small non-zero values" do
      data = [1, 100]
      heights = HealthComponents.sparkline_heights(data)

      # Small value should be at least 10%
      assert List.first(heights) == 10
      assert List.last(heights) == 100
    end

    test "format_change/1 formats positive numbers with plus sign" do
      assert HealthComponents.format_change(15) == "+15%"
    end

    test "format_change/1 formats negative numbers with minus sign" do
      assert HealthComponents.format_change(-10) == "-10%"
    end

    test "format_change/1 formats zero without plus sign" do
      assert HealthComponents.format_change(0) == "0%"
    end

    test "time_ago_in_words/1 formats recent times" do
      now = DateTime.utc_now()

      # Just now (less than 1 minute ago)
      assert HealthComponents.time_ago_in_words(now) == "just now"

      # Minutes ago (uses "min" shorthand)
      minutes_ago = DateTime.add(now, -5, :minute)
      assert HealthComponents.time_ago_in_words(minutes_ago) == "5 min ago"

      # Hours ago
      hours_ago = DateTime.add(now, -3, :hour)
      assert HealthComponents.time_ago_in_words(hours_ago) == "3 hours ago"

      # Days ago
      days_ago = DateTime.add(now, -2, :day)
      assert HealthComponents.time_ago_in_words(days_ago) == "2 days ago"
    end

    test "time_ago_in_words/1 handles nil" do
      assert HealthComponents.time_ago_in_words(nil) == "Never"
    end
  end
end
