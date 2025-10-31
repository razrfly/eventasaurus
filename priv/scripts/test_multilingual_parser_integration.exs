#!/usr/bin/env elixir

# Test script to verify MultilingualDateParser integration with Sortiraparis Transformer
#
# Usage: mix run test_multilingual_parser_integration.exs

alias EventasaurusDiscovery.Sources.Sortiraparis.Transformer

IO.puts("\n🧪 Testing MultilingualDateParser Integration with Sortiraparis Transformer\n")
IO.puts("=" <> String.duplicate("=", 79))

# Test Case 1: French single date
IO.puts("\n📅 Test 1: French single date")
IO.puts("-" <> String.duplicate("-", 79))

french_single_date = %{
  "url" => "/articles/123456-concert-musique-classique",
  "title" => "Concert de musique classique",
  "date_string" => "17 octobre 2025",
  "venue" => %{
    "name" => "Philharmonie de Paris",
    "city" => "Paris",
    "address" => "221 Avenue Jean Jaurès, 75019 Paris"
  }
}

case Transformer.transform_event(french_single_date) do
  {:ok, [event]} ->
    IO.puts("✅ SUCCESS: Parsed French single date")
    IO.puts("   Title: #{event.title}")
    IO.puts("   Starts at: #{event.starts_at}")
    IO.puts("   External ID: #{event.external_id}")
    IO.puts("   Original date string: #{inspect(event.metadata["original_date_string"])}")

  {:error, reason} ->
    IO.puts("❌ FAILED: #{inspect(reason)}")
end

# Test Case 2: French date range (cross-month)
IO.puts("\n📅 Test 2: French date range (cross-month)")
IO.puts("-" <> String.duplicate("-", 79))

french_date_range = %{
  "url" => "/articles/234567-festival-theatre",
  "title" => "Festival de théâtre",
  "date_string" => "du 19 mars au 7 juillet 2025",
  "venue" => %{
    "name" => "Théâtre du Châtelet",
    "city" => "Paris",
    "address" => "1 Place du Châtelet, 75001 Paris"
  }
}

case Transformer.transform_event(french_date_range) do
  {:ok, events} ->
    IO.puts("✅ SUCCESS: Parsed French date range")
    IO.puts("   Title: #{hd(events).title}")
    IO.puts("   Events created: #{length(events)}")
    IO.puts("   Starts at: #{hd(events).starts_at}")
    if length(events) > 1 do
      IO.puts("   Ends at: #{List.last(events).starts_at}")
    end

  {:error, reason} ->
    IO.puts("❌ FAILED: #{inspect(reason)}")
end

# Test Case 3: English single date
IO.puts("\n📅 Test 3: English single date")
IO.puts("-" <> String.duplicate("-", 79))

english_single_date = %{
  "url" => "/articles/345678-rock-concert-accor-arena",
  "title" => "Rock Concert at Accor Arena",
  "date_string" => "October 15, 2025",
  "venue" => %{
    "name" => "Accor Arena",
    "city" => "Paris",
    "address" => "8 Boulevard de Bercy, 75012 Paris"
  }
}

case Transformer.transform_event(english_single_date) do
  {:ok, [event]} ->
    IO.puts("✅ SUCCESS: Parsed English single date")
    IO.puts("   Title: #{event.title}")
    IO.puts("   Starts at: #{event.starts_at}")
    IO.puts("   External ID: #{event.external_id}")

  {:error, reason} ->
    IO.puts("❌ FAILED: #{inspect(reason)}")
end

# Test Case 4: English date range
IO.puts("\n📅 Test 4: English date range")
IO.puts("-" <> String.duplicate("-", 79))

english_date_range = %{
  "url" => "/articles/456789-art-exhibition",
  "title" => "Art Exhibition",
  "date_string" => "October 15, 2025 to January 19, 2026",
  "venue" => %{
    "name" => "Musée d'Orsay",
    "city" => "Paris",
    "address" => "1 Rue de la Légion d'Honneur, 75007 Paris"
  }
}

case Transformer.transform_event(english_date_range) do
  {:ok, events} ->
    IO.puts("✅ SUCCESS: Parsed English date range")
    IO.puts("   Title: #{hd(events).title}")
    IO.puts("   Events created: #{length(events)}")
    IO.puts("   Starts at: #{hd(events).starts_at}")
    if length(events) > 1 do
      IO.puts("   Ends at: #{List.last(events).starts_at}")
    end

  {:error, reason} ->
    IO.puts("❌ FAILED: #{inspect(reason)}")
end

# Test Case 5: Unparseable date (should use unknown occurrence fallback)
IO.puts("\n📅 Test 5: Unknown occurrence fallback")
IO.puts("-" <> String.duplicate("-", 79))

unknown_occurrence = %{
  "url" => "/articles/567890-mystery-event",
  "title" => "Mystery Event",
  "date_string" => "sometime in spring 2025",
  "venue" => %{
    "name" => "La Seine Musicale",
    "city" => "Boulogne-Billancourt",
    "address" => "Île Seguin, 92100 Boulogne-Billancourt"
  }
}

case Transformer.transform_event(unknown_occurrence) do
  {:ok, [event]} ->
    IO.puts("✅ SUCCESS: Unknown occurrence fallback triggered")
    IO.puts("   Title: #{event.title}")
    IO.puts("   Occurrence type: #{event.metadata["occurrence_type"]}")
    IO.puts("   Occurrence fallback: #{event.metadata["occurrence_fallback"]}")
    IO.puts("   Original date string: #{inspect(event.metadata["original_date_string"])}")

  {:error, reason} ->
    IO.puts("❌ FAILED: #{inspect(reason)}")
end

# Test Case 6: French date with ordinals
IO.puts("\n📅 Test 6: French date with ordinals")
IO.puts("-" <> String.duplicate("-", 79))

french_ordinals = %{
  "url" => "/articles/678901-celebration-nouvel-an",
  "title" => "Célébration du Nouvel An",
  "date_string" => "Le 1er janvier 2026",
  "venue" => %{
    "name" => "Champs-Élysées",
    "city" => "Paris",
    "address" => "Avenue des Champs-Élysées, 75008 Paris"
  }
}

case Transformer.transform_event(french_ordinals) do
  {:ok, [event]} ->
    IO.puts("✅ SUCCESS: Parsed French date with ordinals")
    IO.puts("   Title: #{event.title}")
    IO.puts("   Starts at: #{event.starts_at}")

  {:error, reason} ->
    IO.puts("❌ FAILED: #{inspect(reason)}")
end

IO.puts("\n" <> "=" <> String.duplicate("=", 79))
IO.puts("🎉 Integration tests complete!\n")
