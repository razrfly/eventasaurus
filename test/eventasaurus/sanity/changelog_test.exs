defmodule Eventasaurus.Sanity.ChangelogTest do
  use ExUnit.Case, async: true

  alias Eventasaurus.Sanity.Changelog

  describe "transform_entry/1" do
    test "transforms Sanity format to component format" do
      sanity_entry = %{
        "_id" => "abc123",
        "title" => "Test Entry",
        "slug" => "test-entry",
        "date" => "2024-10-15",
        "summary" => "Test summary",
        "changes" => [
          %{"type" => "new", "description" => "New feature"},
          %{"type" => "fixed", "description" => "Bug fix"}
        ],
        "tags" => ["polling", "scheduling"]
      }

      result = Changelog.transform_entry(sanity_entry)

      assert result.id == "abc123"
      assert result.title == "Test Entry"
      assert result.date == "October 15, 2024"
      assert result.iso_date == "2024-10-15"
      assert result.summary == "Test summary"
      assert length(result.changes) == 2
      assert hd(result.changes).type == "new"
      assert hd(result.changes).description == "New feature"
      assert result.tags == ["polling", "scheduling"]
      assert result.image == nil
    end

    test "handles nil tags" do
      entry = %{
        "_id" => "test",
        "title" => "Test",
        "date" => "2024-01-01",
        "summary" => "Summary",
        "changes" => [],
        "tags" => nil
      }

      result = Changelog.transform_entry(entry)
      assert result.tags == []
    end

    test "handles missing tags key" do
      entry = %{
        "_id" => "test",
        "title" => "Test",
        "date" => "2024-01-01",
        "summary" => "Summary",
        "changes" => []
      }

      result = Changelog.transform_entry(entry)
      assert result.tags == []
    end

    test "handles nil date" do
      entry = %{
        "_id" => "test",
        "title" => "Test",
        "date" => nil,
        "summary" => "Summary",
        "changes" => []
      }

      result = Changelog.transform_entry(entry)
      assert result.date == "Unknown date"
    end

    test "handles nil changes" do
      entry = %{
        "_id" => "test",
        "title" => "Test",
        "date" => "2024-01-01",
        "summary" => "Summary",
        "changes" => nil
      }

      result = Changelog.transform_entry(entry)
      assert result.changes == []
    end

    test "extracts image URL from nested structure" do
      entry = %{
        "_id" => "test",
        "title" => "Test",
        "date" => "2024-01-01",
        "summary" => "Summary",
        "changes" => [],
        "image" => %{
          "asset" => %{
            "url" => "https://cdn.sanity.io/images/test.jpg"
          }
        }
      }

      result = Changelog.transform_entry(entry)
      assert result.image == "https://cdn.sanity.io/images/test.jpg"
    end

    test "handles missing image" do
      entry = %{
        "_id" => "test",
        "title" => "Test",
        "date" => "2024-01-01",
        "summary" => "Summary",
        "changes" => [],
        "image" => nil
      }

      result = Changelog.transform_entry(entry)
      assert result.image == nil
    end

    test "marks recent entries as new (within 30 days)" do
      recent_date = Date.utc_today() |> Date.add(-15) |> Date.to_iso8601()

      entry = %{
        "_id" => "recent",
        "title" => "Recent Entry",
        "date" => recent_date,
        "summary" => "Recent summary",
        "changes" => []
      }

      result = Changelog.transform_entry(entry)
      assert result.is_new == true
    end

    test "does not mark old entries as new (older than 30 days)" do
      old_date = Date.utc_today() |> Date.add(-60) |> Date.to_iso8601()

      entry = %{
        "_id" => "old",
        "title" => "Old Entry",
        "date" => old_date,
        "summary" => "Old summary",
        "changes" => []
      }

      result = Changelog.transform_entry(entry)
      assert result.is_new == false
    end

    test "handles nil date for is_new check" do
      entry = %{
        "_id" => "no-date",
        "title" => "No Date Entry",
        "date" => nil,
        "summary" => "Summary",
        "changes" => []
      }

      result = Changelog.transform_entry(entry)
      assert result.is_new == false
    end
  end
end
