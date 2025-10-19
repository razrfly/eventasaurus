defmodule EventasaurusDiscovery.Sources.Sortiraparis.Parsers.DateParserTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Parsers.DateParser

  describe "parse/1 - English single dates" do
    test "parses simple English date" do
      assert DateParser.parse("October 15, 2025") == {:ok, "2025-10-15"}
    end

    test "parses English date without comma" do
      assert DateParser.parse("October 15 2025") == {:ok, "2025-10-15"}
    end

    test "parses English date with day name" do
      assert DateParser.parse("Friday, October 31, 2025") == {:ok, "2025-10-31"}
    end

    test "parses English date with ordinal suffix" do
      assert DateParser.parse("October 1st, 2025") == {:ok, "2025-10-01"}
      assert DateParser.parse("October 2nd, 2025") == {:ok, "2025-10-02"}
      assert DateParser.parse("October 3rd, 2025") == {:ok, "2025-10-03"}
      assert DateParser.parse("October 4th, 2025") == {:ok, "2025-10-04"}
    end

    test "parses abbreviated month names" do
      assert DateParser.parse("Jan 15, 2025") == {:ok, "2025-01-15"}
      assert DateParser.parse("Feb 28, 2025") == {:ok, "2025-02-28"}
      assert DateParser.parse("Dec 31, 2025") == {:ok, "2025-12-31"}
    end

    test "parses with 'The' article" do
      assert DateParser.parse("The October 15, 2025") == {:ok, "2025-10-15"}
    end
  end

  describe "parse/1 - French single dates" do
    test "parses simple French date" do
      assert DateParser.parse("17 octobre 2025") == {:ok, "2025-10-17"}
    end

    test "parses French date with day name" do
      assert DateParser.parse("vendredi 31 octobre 2025") == {:ok, "2025-10-31"}
    end

    test "parses French date with 'Le' article" do
      assert DateParser.parse("Le 19 avril 2025") == {:ok, "2025-04-19"}
    end

    test "parses French date with 1er ordinal" do
      assert DateParser.parse("1er janvier 2026") == {:ok, "2026-01-01"}
      assert DateParser.parse("Le 1er décembre 2025") == {:ok, "2025-12-01"}
    end

    test "parses French date with 2e ordinal" do
      assert DateParser.parse("2e février 2026") == {:ok, "2026-02-02"}
    end

    test "parses all French months" do
      assert DateParser.parse("15 janvier 2025") == {:ok, "2025-01-15"}
      assert DateParser.parse("15 février 2025") == {:ok, "2025-02-15"}
      assert DateParser.parse("15 mars 2025") == {:ok, "2025-03-15"}
      assert DateParser.parse("15 avril 2025") == {:ok, "2025-04-15"}
      assert DateParser.parse("15 mai 2025") == {:ok, "2025-05-15"}
      assert DateParser.parse("15 juin 2025") == {:ok, "2025-06-15"}
      assert DateParser.parse("15 juillet 2025") == {:ok, "2025-07-15"}
      assert DateParser.parse("15 août 2025") == {:ok, "2025-08-15"}
      assert DateParser.parse("15 septembre 2025") == {:ok, "2025-09-15"}
      assert DateParser.parse("15 octobre 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("15 novembre 2025") == {:ok, "2025-11-15"}
      assert DateParser.parse("15 décembre 2025") == {:ok, "2025-12-15"}
    end

    test "parses abbreviated French month names" do
      assert DateParser.parse("15 janv 2025") == {:ok, "2025-01-15"}
      assert DateParser.parse("15 févr 2025") == {:ok, "2025-02-15"}
      assert DateParser.parse("15 avr 2025") == {:ok, "2025-04-15"}
      assert DateParser.parse("15 juil 2025") == {:ok, "2025-07-15"}
      assert DateParser.parse("15 sept 2025") == {:ok, "2025-09-15"}
      assert DateParser.parse("15 déc 2025") == {:ok, "2025-12-15"}
    end

    test "parses French day names" do
      assert DateParser.parse("lundi 15 octobre 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("mardi 15 octobre 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("mercredi 15 octobre 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("jeudi 15 octobre 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("vendredi 15 octobre 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("samedi 15 octobre 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("dimanche 15 octobre 2025") == {:ok, "2025-10-15"}
    end
  end

  describe "parse/1 - mixed case and whitespace" do
    test "handles uppercase text" do
      assert DateParser.parse("OCTOBER 15, 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("17 OCTOBRE 2025") == {:ok, "2025-10-17"}
    end

    test "handles extra whitespace" do
      assert DateParser.parse("  October   15  ,  2025  ") == {:ok, "2025-10-15"}
      assert DateParser.parse("17    octobre    2025") == {:ok, "2025-10-17"}
    end

    test "handles mixed case" do
      assert DateParser.parse("October 15, 2025") == {:ok, "2025-10-15"}
      assert DateParser.parse("17 Octobre 2025") == {:ok, "2025-10-17"}
    end
  end

  describe "parse/1 - edge cases" do
    test "handles leap year dates" do
      assert DateParser.parse("February 29, 2024") == {:ok, "2024-02-29"}
      assert DateParser.parse("29 février 2024") == {:ok, "2024-02-29"}
    end

    test "handles year boundaries" do
      assert DateParser.parse("January 1, 2025") == {:ok, "2025-01-01"}
      assert DateParser.parse("December 31, 2025") == {:ok, "2025-12-31"}
    end

    test "handles dates in context" do
      text = "The event will take place on October 15, 2025 at the venue."
      assert DateParser.parse(text) == {:ok, "2025-10-15"}
    end

    test "handles French dates in context" do
      text = "L'événement aura lieu le 17 octobre 2025 dans la salle."
      assert DateParser.parse(text) == {:ok, "2025-10-17"}
    end
  end

  describe "parse/1 - error handling" do
    test "returns error for invalid date" do
      # February 30 doesn't exist
      assert {:error, {:date_parse_failed, _}} = DateParser.parse("February 30, 2025")
    end

    test "returns error for missing month" do
      assert {:error, :month_not_found} = DateParser.parse("15 2025")
    end

    test "returns error for missing year" do
      assert {:error, :year_not_found} = DateParser.parse("October 15")
    end

    test "returns error for missing day" do
      assert {:error, :day_not_found} = DateParser.parse("October 2025")
    end

    test "returns error for completely invalid text" do
      assert {:error, _} = DateParser.parse("not a date at all")
    end

    test "returns error for nil input" do
      assert {:error, :invalid_input} = DateParser.parse(nil)
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_input} = DateParser.parse(123)
    end
  end

  describe "parse/1 - English date ranges" do
    test "parses simple English date range with same year" do
      assert DateParser.parse("October 15 to November 20, 2025") ==
               {:ok, %{start_date: "2025-10-15", end_date: "2025-11-20"}}
    end

    test "parses English date range across years" do
      assert DateParser.parse("October 15, 2025 to January 19, 2026") ==
               {:ok, %{start_date: "2025-10-15", end_date: "2026-01-19"}}
    end

    test "parses English date range with full dates" do
      assert DateParser.parse("December 1, 2025 to February 28, 2026") ==
               {:ok, %{start_date: "2025-12-01", end_date: "2026-02-28"}}
    end

    test "parses English date range with ordinals" do
      assert DateParser.parse("October 1st, 2025 to October 31st, 2025") ==
               {:ok, %{start_date: "2025-10-01", end_date: "2025-10-31"}}
    end
  end

  describe "parse/1 - French date ranges" do
    test "parses simple French date range" do
      assert DateParser.parse("15 octobre au 20 novembre 2025") ==
               {:ok, %{start_date: "2025-10-15", end_date: "2025-11-20"}}
    end

    test "parses French date range with 'Du...au' pattern" do
      assert DateParser.parse("Du 1er janvier au 15 février 2026") ==
               {:ok, %{start_date: "2026-01-01", end_date: "2026-02-15"}}
    end

    test "parses French date range across years" do
      assert DateParser.parse("15 octobre 2025 au 19 janvier 2026") ==
               {:ok, %{start_date: "2025-10-15", end_date: "2026-01-19"}}
    end

    test "parses French date range with ordinals" do
      assert DateParser.parse("Du 1er au 31 décembre 2025") ==
               {:ok, %{start_date: "2025-12-01", end_date: "2025-12-31"}}
    end
  end

  describe "parse/1 - date range edge cases" do
    test "handles date range with extra whitespace" do
      assert DateParser.parse("  October  15  ,  2025   to   January  19  ,  2026  ") ==
               {:ok, %{start_date: "2025-10-15", end_date: "2026-01-19"}}
    end

    test "handles date range with mixed case" do
      assert DateParser.parse("OCTOBER 15, 2025 TO JANUARY 19, 2026") ==
               {:ok, %{start_date: "2025-10-15", end_date: "2026-01-19"}}
    end

    test "handles French date range with mixed case" do
      assert DateParser.parse("DU 1ER JANVIER AU 15 FÉVRIER 2026") ==
               {:ok, %{start_date: "2026-01-01", end_date: "2026-02-15"}}
    end
  end

  describe "parse/1 - date range error handling" do
    test "returns error for invalid start date in range" do
      assert {:error, {:date_parse_failed, _}} =
               DateParser.parse("February 30, 2025 to March 1, 2025")
    end

    test "returns error for invalid end date in range" do
      assert {:error, {:date_parse_failed, _}} =
               DateParser.parse("February 28, 2025 to February 30, 2025")
    end

    test "returns error for malformed range" do
      assert {:error, _} = DateParser.parse("October 15, 2025 to")
    end
  end

  describe "parse/1 - real Sortiraparis examples" do
    test "parses cinema release date" do
      # From: https://www.sortiraparis.com/loisirs/cinema/articles/335280-film-un-fantome-dans-la-bataille-2025
      assert DateParser.parse("17 octobre 2025") == {:ok, "2025-10-17"}
    end

    test "parses exhibition date" do
      # Common pattern in exhibition articles
      assert DateParser.parse("Le 19 avril 2025") == {:ok, "2025-04-19"}
    end

    test "parses concert date with day name" do
      # Common pattern in concert articles
      assert DateParser.parse("vendredi 31 octobre 2025") == {:ok, "2025-10-31"}
    end

    test "parses exhibition date range" do
      # Common pattern for exhibitions
      assert DateParser.parse("Du 1er janvier au 15 février 2026") ==
               {:ok, %{start_date: "2026-01-01", end_date: "2026-02-15"}}
    end

    test "parses English event date range" do
      # Common pattern for English events
      assert DateParser.parse("October 15, 2025 to January 19, 2026") ==
               {:ok, %{start_date: "2025-10-15", end_date: "2026-01-19"}}
    end
  end

  describe "parse/1 - time extraction" do
    test "parses English 12-hour time with PM" do
      assert DateParser.parse("Sunday 26 October 2025 at 8pm") == {:ok, "2025-10-26T20:00:00"}
      assert DateParser.parse("Sunday 26 October 2025 at 8 pm") == {:ok, "2025-10-26T20:00:00"}
      assert DateParser.parse("Sunday 26 October 2025 at 8 PM") == {:ok, "2025-10-26T20:00:00"}
    end

    test "parses English 12-hour time with AM" do
      assert DateParser.parse("Sunday 26 October 2025 at 9am") == {:ok, "2025-10-26T09:00:00"}
      assert DateParser.parse("Sunday 26 October 2025 at 9 AM") == {:ok, "2025-10-26T09:00:00"}
    end

    test "parses English 12-hour time with minutes" do
      assert DateParser.parse("26 October 2025 at 8:30pm") == {:ok, "2025-10-26T20:30:00"}
      assert DateParser.parse("26 October 2025 at 8:30 PM") == {:ok, "2025-10-26T20:30:00"}
      assert DateParser.parse("26 October 2025 at 2:45pm") == {:ok, "2025-10-26T14:45:00"}
    end

    test "parses English 24-hour time" do
      assert DateParser.parse("26 October 2025 at 20:00") == {:ok, "2025-10-26T20:00:00"}
      assert DateParser.parse("26 October 2025 at 14:30") == {:ok, "2025-10-26T14:30:00"}
      assert DateParser.parse("26 October 2025 at 09:15") == {:ok, "2025-10-26T09:15:00"}
    end

    test "parses French time with 'h'" do
      assert DateParser.parse("17 octobre 2025 à 20h") == {:ok, "2025-10-17T20:00:00"}
      assert DateParser.parse("17 octobre 2025 à 14h") == {:ok, "2025-10-17T14:00:00"}
    end

    test "parses French time with minutes" do
      assert DateParser.parse("17 octobre 2025 à 20h30") == {:ok, "2025-10-17T20:30:00"}
      assert DateParser.parse("17 octobre 2025 à 14h45") == {:ok, "2025-10-17T14:45:00"}
    end

    test "handles dates without time (returns date-only format)" do
      assert DateParser.parse("Sunday 26 October 2025") == {:ok, "2025-10-26"}
      assert DateParser.parse("17 octobre 2025") == {:ok, "2025-10-17"}
    end

    test "handles time in context" do
      text = "The event will take place on October 26, 2025 at 8pm at the venue."
      assert DateParser.parse(text) == {:ok, "2025-10-26T20:00:00"}
    end

    test "handles French time in context" do
      text = "L'événement aura lieu le 17 octobre 2025 à 20h dans la salle."
      assert DateParser.parse(text) == {:ok, "2025-10-17T20:00:00"}
    end

    test "handles noon and midnight" do
      assert DateParser.parse("26 October 2025 at 12pm") == {:ok, "2025-10-26T12:00:00"}
      assert DateParser.parse("26 October 2025 at 12am") == {:ok, "2025-10-26T00:00:00"}
    end
  end
end
