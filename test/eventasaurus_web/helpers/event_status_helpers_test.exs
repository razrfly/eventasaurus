defmodule EventasaurusWeb.Helpers.EventStatusHelpersTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.Helpers.EventStatusHelpers

  describe "friendly_status_message/2" do
    test "confirmed event with tickets - badge format" do
      event = %{status: :confirmed, is_ticketed: true}
      assert EventStatusHelpers.friendly_status_message(event, :badge) == "Open for Registration"
    end

    test "confirmed event with tickets - compact format" do
      event = %{status: :confirmed, is_ticketed: true}
      assert EventStatusHelpers.friendly_status_message(event, :compact) == "Registration Open"
    end

    test "confirmed event with tickets - detailed format" do
      event = %{status: :confirmed, is_ticketed: true}

      assert EventStatusHelpers.friendly_status_message(event, :detailed) ==
               "Event confirmed and open for registration"
    end

    test "confirmed free event - badge format" do
      event = %{status: :confirmed, is_ticketed: false}
      assert EventStatusHelpers.friendly_status_message(event, :badge) == "Ready to Go"
    end

    test "confirmed free event - compact format" do
      event = %{status: :confirmed, is_ticketed: false}
      assert EventStatusHelpers.friendly_status_message(event, :compact) == "Event Ready"
    end

    test "polling event - badge format" do
      event = %{status: :polling}
      assert EventStatusHelpers.friendly_status_message(event, :badge) == "Getting Feedback"
    end

    test "polling event - compact format" do
      event = %{status: :polling}
      assert EventStatusHelpers.friendly_status_message(event, :compact) == "Collecting Votes"
    end

    test "polling event - detailed format" do
      event = %{status: :polling}

      assert EventStatusHelpers.friendly_status_message(event, :detailed) ==
               "Collecting feedback from attendees"
    end

    test "crowdfunding threshold event - badge format" do
      event = %{status: :threshold, threshold_type: "revenue", is_ticketed: true}
      assert EventStatusHelpers.friendly_status_message(event, :badge) == "Crowdfunding Active"
    end

    test "crowdfunding threshold event - compact format" do
      event = %{status: :threshold, threshold_type: "revenue", is_ticketed: true}
      assert EventStatusHelpers.friendly_status_message(event, :compact) == "Funding in Progress"
    end

    test "interest validation threshold event - badge format" do
      event = %{status: :threshold, threshold_type: "attendee_count"}
      assert EventStatusHelpers.friendly_status_message(event, :badge) == "Validating Interest"
    end

    test "interest validation threshold event - compact format" do
      event = %{status: :threshold, threshold_type: "attendee_count"}
      assert EventStatusHelpers.friendly_status_message(event, :compact) == "Checking Interest"
    end

    test "draft event - badge format" do
      event = %{status: :draft}
      assert EventStatusHelpers.friendly_status_message(event, :badge) == "In Planning"
    end

    test "draft event - compact format" do
      event = %{status: :draft}
      assert EventStatusHelpers.friendly_status_message(event, :compact) == "Planning Stage"
    end

    test "canceled event" do
      event = %{status: :canceled}
      assert EventStatusHelpers.friendly_status_message(event, :badge) == "Canceled"
      assert EventStatusHelpers.friendly_status_message(event, :compact) == "Event Canceled"
    end

    test "unknown status defaults" do
      event = %{status: :unknown}
      assert EventStatusHelpers.friendly_status_message(event) == "Status Unknown"
    end
  end

  describe "contextual_info/2" do
    test "crowdfunding with progress" do
      event = %{
        status: :threshold,
        threshold_type: "revenue",
        is_ticketed: true,
        threshold_revenue_cents: 100_000,
        current_revenue_cents: 45_000
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Raised $450 of $1000 goal ($550 to go)"
    end

    test "crowdfunding goal reached" do
      event = %{
        status: :threshold,
        threshold_type: "revenue",
        is_ticketed: true,
        threshold_revenue_cents: 100_000,
        current_revenue_cents: 150_000
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Goal reached! Raised $1500 of $1000"
    end

    test "crowdfunding with only goal set" do
      event = %{
        status: :threshold,
        threshold_type: "revenue",
        is_ticketed: true,
        threshold_revenue_cents: 100_000
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Funding goal: $1000"
    end

    test "interest validation with progress needed" do
      event = %{
        status: :threshold,
        threshold_type: "attendee_count",
        threshold_count: 50,
        participant_count: 35
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Waiting for 15 more people to sign up"
    end

    test "interest validation goal reached" do
      event = %{
        status: :threshold,
        threshold_type: "attendee_count",
        threshold_count: 50,
        participant_count: 75
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Interest goal reached! 75 people signed up"
    end

    test "interest validation with only goal set" do
      event = %{
        status: :threshold,
        threshold_type: "attendee_count",
        threshold_count: 50
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Need 50 people to confirm"
    end

    test "polling with deadline in minutes" do
      # 30 minutes
      future_time = DateTime.utc_now() |> DateTime.add(1800, :second)
      event = %{status: :polling, polling_deadline: future_time}

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Polling closes in 30 minutes"
    end

    test "polling with deadline in hours" do
      # 2 hours
      future_time = DateTime.utc_now() |> DateTime.add(7200, :second)
      event = %{status: :polling, polling_deadline: future_time}

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Polling closes in 2 hours"
    end

    test "polling with deadline in days" do
      # 3 days
      future_time = DateTime.utc_now() |> DateTime.add(259_200, :second)
      event = %{status: :polling, polling_deadline: future_time}

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Polling closes in 3 days"
    end

    test "polling deadline has passed" do
      # 1 hour ago
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second)
      event = %{status: :polling, polling_deadline: past_time}

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Polling has ended"
    end

    test "confirmed event with available tickets" do
      event = %{
        status: :confirmed,
        is_ticketed: true,
        available_tickets: 25
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "25 tickets remaining"
    end

    test "confirmed event requiring registration" do
      event = %{
        status: :confirmed,
        is_ticketed: true,
        available_tickets: 0
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "Registration required"
    end

    test "confirmed event with participants" do
      event = %{
        status: :confirmed,
        is_ticketed: false,
        participant_count: 15
      }

      result = EventStatusHelpers.contextual_info(event)
      assert result == "15 people attending"
    end

    test "draft event" do
      event = %{status: :draft}
      result = EventStatusHelpers.contextual_info(event)
      assert result == "Details being finalized"
    end

    test "canceled event" do
      event = %{status: :canceled}
      result = EventStatusHelpers.contextual_info(event)
      assert result == "Event will not take place"
    end
  end

  describe "complete_status_display/2" do
    test "returns complete status information" do
      event = %{
        status: :threshold,
        threshold_type: "attendee_count",
        threshold_count: 50,
        participant_count: 35
      }

      result = EventStatusHelpers.complete_status_display(event, :compact)

      assert result.primary == "Checking Interest"
      assert result.secondary == "Waiting for 15 more people to sign up"
      assert result.has_context == true
      assert result.css_class == "bg-yellow-100 text-yellow-800"
      assert result.icon == "🎯"
    end

    test "handles events without contextual info" do
      event = %{status: :draft}

      result = EventStatusHelpers.complete_status_display(event, :badge)

      assert result.primary == "In Planning"
      assert result.secondary == "Details being finalized"
      assert result.has_context == true
      assert result.css_class == "bg-gray-100 text-gray-800"
      assert result.icon == "📝"
    end
  end

  describe "status_css_class/1" do
    test "returns correct CSS classes for each status" do
      assert EventStatusHelpers.status_css_class(%{status: :confirmed}) ==
               "bg-green-100 text-green-800"

      assert EventStatusHelpers.status_css_class(%{status: :polling}) ==
               "bg-blue-100 text-blue-800"

      assert EventStatusHelpers.status_css_class(%{status: :draft}) == "bg-gray-100 text-gray-800"

      assert EventStatusHelpers.status_css_class(%{status: :canceled}) ==
               "bg-red-100 text-red-800"
    end

    test "returns different classes for threshold subtypes" do
      crowdfunding = %{status: :threshold, threshold_type: "revenue", is_ticketed: true}
      interest = %{status: :threshold, threshold_type: "attendee_count"}

      assert EventStatusHelpers.status_css_class(crowdfunding) == "bg-purple-100 text-purple-800"
      assert EventStatusHelpers.status_css_class(interest) == "bg-yellow-100 text-yellow-800"
    end
  end

  describe "status_icon/1" do
    test "returns correct icons for each status" do
      assert EventStatusHelpers.status_icon(%{status: :confirmed}) == "✓"
      assert EventStatusHelpers.status_icon(%{status: :polling}) == "📊"
      assert EventStatusHelpers.status_icon(%{status: :draft}) == "📝"
      assert EventStatusHelpers.status_icon(%{status: :canceled}) == "❌"
    end

    test "returns different icons for threshold subtypes" do
      crowdfunding = %{status: :threshold, threshold_type: "revenue", is_ticketed: true}
      interest = %{status: :threshold, threshold_type: "attendee_count"}

      assert EventStatusHelpers.status_icon(crowdfunding) == "💰"
      assert EventStatusHelpers.status_icon(interest) == "🎯"
    end
  end
end
