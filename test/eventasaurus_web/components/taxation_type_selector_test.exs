defmodule EventasaurusWeb.Components.TaxationTypeSelectorTest do
  @moduledoc """
  Unit tests for the taxation_type_selector component.
  Covers visual rendering, accessibility, keyboard navigation,
  screen reader support, tooltip functionality, and error handling.
  """

  use EventasaurusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EventasaurusWeb.CoreComponents

  # Helper function to create a mock form field
  defp create_mock_field(name, value \\ "ticketed_event", errors \\ []) do
    %{
      id: "event_#{name}",
      name: "event[#{name}]",
      value: value,
      errors: errors
    }
  end

  describe "taxation_type_selector/1 visual rendering" do
    test "renders basic component structure" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "taxation-type-selector"
      assert html =~ "phx-hook=\"TaxationTypeValidator\""
      assert html =~ "Event Taxation Classification"
      assert html =~ "Ticketed Event"
      assert html =~ "Contribution Collection"
    end

    test "renders both radio button options with descriptions" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "value=\"ticketed_event\""
      assert html =~ "Standard events with paid tickets"
      assert html =~ "value=\"contribution_collection\""
      assert html =~ "Donation-based events and fundraising"
    end

    test "shows correct selected value" do
      field = create_mock_field("taxation_type", "contribution_collection")

      assigns = %{
        field: field,
        value: "contribution_collection",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "checked"
      assert html =~ "value=\"contribution_collection\""
    end

    test "applies custom CSS classes" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: "custom-class"
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "custom-class"
    end

    test "generates valid HTML structure" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "<fieldset"
      assert html =~ "<legend"
      assert html =~ "role=\"radiogroup\""
      assert html =~ "aria-required=\"true\""
    end
  end

  describe "taxation_type_selector/1 accessibility" do
    test "includes proper ARIA attributes" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "role=\"radiogroup\""
      assert html =~ "aria-required=\"true\""
      assert html =~ "aria-labelledby=\"taxation-type-legend\""
      assert html =~ "aria-describedby=\"taxation-type-description taxation-type-help\""
    end

    test "provides screen reader content" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "Instructions for screen readers"
      assert html =~ "Use arrow keys to navigate"
      assert html =~ "class=\"sr-only\""
    end

    test "renders proper focus indicators" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "focus-within:ring-2"
      assert html =~ "focus:ring-blue-500"
    end

    test "indicates required fields properly" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "aria-label=\"required\""
      assert html =~ "text-red-500"
    end
  end

  describe "taxation_type_selector/1 keyboard navigation" do
    test "supports radio group keyboard navigation" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "role=\"radiogroup\""
      assert html =~ "Use arrow keys to navigate"
      assert html =~ "Press Space or Enter to select"
    end
  end

  describe "taxation_type_selector/1 tooltip functionality" do
    test "includes interactive tooltip with help content" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "data-role=\"help-tooltip\""
      assert html =~ "Taxation Classification Guide"
      assert html =~ "phx-click-away"
      assert html =~ "Traditional events with paid admission tickets"
    end
  end

  describe "taxation_type_selector/1 error state handling" do
    test "displays no errors when errors list is empty" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      refute html =~ "data-role=\"error-container\""
      refute html =~ "text-red-700"
    end

    test "displays single error message" do
      field = create_mock_field("taxation_type", "", [{"can't be blank", []}])

      assigns = %{
        field: field,
        value: "",
        errors: [{"can't be blank", []}],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "Please select a taxation type for your event"
      assert html =~ "text-red-700"
      assert html =~ "role=\"alert\""
    end

    test "displays multiple error messages" do
      field = create_mock_field("taxation_type", "ticketed_event", [{"can't be blank", []}, {"is invalid", []}])

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [{"can't be blank", []}, {"is invalid", []}],
        required: true
      }

      html = render_component(&taxation_type_selector/1, assigns)

      # Check that error container is present
      assert html =~ "data-role=\"error-container\""

      # Check for transformed error messages (not raw text)
      assert html =~ "Please select a taxation type for your event"
      assert html =~ "Please choose either Ticketless Event, Ticketed Event, or Contribution Collection"

      # Check for help text in errors
      assert html =~ "Need help deciding? Click"

      # Check for proper ARIA attributes
      assert html =~ "role=\"alert\""
      assert html =~ "aria-live=\"polite\""
      assert html =~ "aria-atomic=\"true\""
    end

    test "translates business rule error messages" do
      error_msg = "Contribution collection events cannot have ticketing enabled"
      field = create_mock_field("taxation_type", "contribution_collection", [{error_msg, []}])

      assigns = %{
        field: field,
        value: "contribution_collection",
        errors: [{error_msg, []}],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ error_msg
      assert html =~ "text-red-700"
    end

    test "handles custom error messages" do
      custom_error = "Custom validation error"
      field = create_mock_field("taxation_type", "", [{custom_error, []}])

      assigns = %{
        field: field,
        value: "",
        errors: [{custom_error, []}],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ custom_error
      assert html =~ "text-red-700"
    end

    test "no longer displays smart default reasoning (removed from UI)" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        reasoning: "Recommended for most events with admission fees or ticket sales"
      }

      html = render_component(&taxation_type_selector/1, assigns)

      # Check that reasoning is NOT displayed (removed from component)
      refute html =~ "Smart Default:"
      refute html =~ "Recommended for most events with admission fees or ticket sales"
      # Component should still work normally
      assert html =~ "Ticketed Event"
      assert html =~ "Contribution Collection"
    end

    test "does not display reasoning when empty" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        reasoning: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      # Check that reasoning section is not displayed
      refute html =~ "Smart Default:"
    end

    test "does not display reasoning when there are errors" do
      field = create_mock_field("taxation_type")

      assigns = %{
        field: field,
        value: "",
        errors: [{"can't be blank", []}],
        required: true,
        reasoning: "Some reasoning text"
      }

      html = render_component(&taxation_type_selector/1, assigns)

      # Check that reasoning is not displayed when errors are present
      refute html =~ "Smart Default:"
      refute html =~ "Some reasoning text"
      # But error should be displayed
      assert html =~ "Please select a taxation type"
    end
  end

  describe "taxation_type_selector/1 success state handling" do
    test "shows confirmation for ticketless event selection" do
      field = create_mock_field("taxation_type", "ticketless")

      assigns = %{
        field: field,
        value: "ticketless",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "Selected: Ticketless Event"
      assert html =~ "Free event with no payment processing"
      assert html =~ "text-green-700"
    end

    test "shows confirmation for ticketed event selection" do
      field = create_mock_field("taxation_type", "ticketed_event")

      assigns = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "Selected: Ticketed Event"
      assert html =~ "Standard event with paid tickets"
      assert html =~ "text-green-700"
    end

    test "shows confirmation for contribution collection selection" do
      field = create_mock_field("taxation_type", "contribution_collection")

      assigns = %{
        field: field,
        value: "contribution_collection",
        errors: [],
        required: true,
        class: ""
      }

      html = render_component(&taxation_type_selector/1, assigns)

      assert html =~ "Selected: Contribution Collection"
      assert html =~ "Donation-based event"
      assert html =~ "text-green-700"
    end
  end

  describe "taxation_type_selector/1 configurability" do
    test "handles both required and optional field configurations" do
      # Test required field
      field = create_mock_field("taxation_type")

      assigns_required = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: true,
        class: ""
      }

      html_required = render_component(&taxation_type_selector/1, assigns_required)
      assert html_required =~ "aria-required=\"true\""
      assert html_required =~ "text-red-500"

      # Test optional field
      assigns_optional = %{
        field: field,
        value: "ticketed_event",
        errors: [],
        required: false,
        class: ""
      }

      html_optional = render_component(&taxation_type_selector/1, assigns_optional)
      assert html_optional =~ "aria-required=\"false\""
      refute html_optional =~ "aria-label=\"required\""
    end
  end
end
