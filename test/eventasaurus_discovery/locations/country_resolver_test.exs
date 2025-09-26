defmodule EventasaurusDiscovery.Locations.CountryResolverTest do
  use ExUnit.Case, async: true
  alias EventasaurusDiscovery.Locations.CountryResolver

  describe "resolve/1" do
    test "resolves Polish country names" do
      assert country = CountryResolver.resolve("Polska")
      assert country.alpha2 == "PL"
      assert country.name == "Poland"

      assert country = CountryResolver.resolve("polska")
      assert country.alpha2 == "PL"

      assert country = CountryResolver.resolve("POLSKA")
      assert country.alpha2 == "PL"
    end

    test "resolves German country names" do
      assert country = CountryResolver.resolve("Deutschland")
      assert country.alpha2 == "DE"
      assert country.name == "Germany"

      assert country = CountryResolver.resolve("Niemcy")
      assert country.alpha2 == "DE"

      assert country = CountryResolver.resolve("Allemagne")
      assert country.alpha2 == "DE"
    end

    test "resolves French country names" do
      assert country = CountryResolver.resolve("Francja")
      assert country.alpha2 == "FR"

      assert country = CountryResolver.resolve("Frankreich")
      assert country.alpha2 == "FR"
    end

    test "resolves English country names (standard behavior)" do
      assert country = CountryResolver.resolve("Poland")
      assert country.alpha2 == "PL"

      assert country = CountryResolver.resolve("Germany")
      assert country.alpha2 == "DE"

      assert country = CountryResolver.resolve("France")
      assert country.alpha2 == "FR"
    end

    test "resolves ISO codes directly" do
      assert country = CountryResolver.resolve("PL")
      assert country.alpha2 == "PL"

      assert country = CountryResolver.resolve("DE")
      assert country.alpha2 == "DE"

      assert country = CountryResolver.resolve("FR")
      assert country.alpha2 == "FR"
    end

    test "handles variations and edge cases" do
      assert country = CountryResolver.resolve("UK")
      assert country.alpha2 == "GB"

      assert country = CountryResolver.resolve("USA")
      assert country.alpha2 == "US"

      assert country = CountryResolver.resolve("Holland")
      assert country.alpha2 == "NL"
    end

    test "returns nil for unknown countries" do
      assert nil == CountryResolver.resolve("Nonexistentland")
      assert nil == CountryResolver.resolve("XYZ123")
      assert nil == CountryResolver.resolve("")
      assert nil == CountryResolver.resolve(nil)
    end

    test "handles whitespace and case variations" do
      assert country = CountryResolver.resolve("  Polska  ")
      assert country.alpha2 == "PL"

      assert country = CountryResolver.resolve("\nDeutschland\t")
      assert country.alpha2 == "DE"
    end
  end

  describe "get_code/1" do
    test "returns ISO code for valid country names" do
      assert "PL" == CountryResolver.get_code("Polska")
      assert "DE" == CountryResolver.get_code("Deutschland")
      assert "FR" == CountryResolver.get_code("Francja")
    end

    test "returns nil for unknown countries" do
      assert nil == CountryResolver.get_code("Nonexistentland")
      assert nil == CountryResolver.get_code(nil)
    end
  end

  describe "has_translation?/1" do
    test "returns true for countries with translations" do
      assert CountryResolver.has_translation?("Polska")
      assert CountryResolver.has_translation?("Deutschland")
      assert CountryResolver.has_translation?("Niemcy")
    end

    test "returns false for countries without translations" do
      refute CountryResolver.has_translation?("Nonexistentland")
      refute CountryResolver.has_translation?(nil)
      refute CountryResolver.has_translation?(123)
    end
  end

  describe "real-world scenarios" do
    test "handles Ticketmaster localized responses" do
      # Polish locale
      assert country = CountryResolver.resolve("Polska")
      assert country.name == "Poland"

      # German locale
      assert country = CountryResolver.resolve("Deutschland")
      assert country.name == "Germany"

      # Spanish locale
      assert country = CountryResolver.resolve("España")
      assert country.name == "Spain"

      # Italian locale
      assert country = CountryResolver.resolve("Italia")
      assert country.name == "Italy"
    end

    test "handles Czech country variations" do
      assert country = CountryResolver.resolve("Czechy")
      assert country.alpha2 == "CZ"

      assert country = CountryResolver.resolve("Česko")
      assert country.alpha2 == "CZ"

      assert country = CountryResolver.resolve("Czech Republic")
      assert country.alpha2 == "CZ"
    end

    test "handles multilingual UK/Great Britain variations" do
      assert country = CountryResolver.resolve("Wielka Brytania")
      assert country.alpha2 == "GB"

      assert country = CountryResolver.resolve("United Kingdom")
      assert country.alpha2 == "GB"

      assert country = CountryResolver.resolve("UK")
      assert country.alpha2 == "GB"

      assert country = CountryResolver.resolve("Royaume-Uni")
      assert country.alpha2 == "GB"
    end
  end
end