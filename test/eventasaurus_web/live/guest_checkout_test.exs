defmodule EventasaurusWeb.GuestCheckoutTest do
  use EventasaurusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "guest checkout form validation works" do
    # Test that the validation functions work as expected
    alias EventasaurusWeb.CheckoutLive

    # Test valid guest form
    valid_form = %{"name" => "John Doe", "email" => "john@example.com"}
    assert {:ok, %{name: "John Doe", email: "john@example.com"}} =
      apply(CheckoutLive, :validate_guest_form, [valid_form])

    # Test empty name
    invalid_form = %{"name" => "", "email" => "john@example.com"}
    assert {:error, errors} = apply(CheckoutLive, :validate_guest_form, [invalid_form])
    assert "Name is required" in errors

    # Test empty email
    invalid_form = %{"name" => "John Doe", "email" => ""}
    assert {:error, errors} = apply(CheckoutLive, :validate_guest_form, [invalid_form])
    assert "Email is required" in errors

    # Test invalid email format
    invalid_form = %{"name" => "John Doe", "email" => "invalid-email"}
    assert {:error, errors} = apply(CheckoutLive, :validate_guest_form, [invalid_form])
    assert "Email format is invalid" in errors
  end

  test "email validation function works correctly" do
    alias EventasaurusWeb.CheckoutLive

    # Valid emails
    assert apply(CheckoutLive, :valid_email?, ["test@example.com"])
    assert apply(CheckoutLive, :valid_email?, ["user.name@domain.co.uk"])
    assert apply(CheckoutLive, :valid_email?, ["user+tag@example.org"])

    # Invalid emails
    refute apply(CheckoutLive, :valid_email?, ["invalid-email"])
    refute apply(CheckoutLive, :valid_email?, ["user@"])
    refute apply(CheckoutLive, :valid_email?, ["@example.com"])
    refute apply(CheckoutLive, :valid_email?, ["user name@example.com"])
  end
end
