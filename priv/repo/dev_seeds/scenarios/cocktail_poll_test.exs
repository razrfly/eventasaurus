# ============================================================================
# ⚠️ TEST DATA SEED: Cocktail Poll Test Scenario
# ============================================================================
#
# ⚠️ WARNING: This is TEST DATA and should be moved to:
#    priv/repo/dev_seeds/scenarios/cocktail_poll_test.exs
#    See Issue #2239 for reorganization plan.
#
# Purpose:
#   Creates a cocktail poll with real CocktailDB data for testing the
#   cocktail voting feature. Uses actual cocktail recipes and images.
#
# When to run:
#   - DEVELOPMENT ONLY - Do not run in production
#   - After running main development seeds (mix seed.dev)
#   - When testing cocktail poll feature or mobile UI optimizations
#
# Dependencies:
#   - REQUIRED: At least one event must exist (uses most recent event)
#
# Idempotency:
#   - YES: Checks if event already has a cocktail poll
#   - Safe to run multiple times
#
# Data created:
#   - Cocktail poll with title "What cocktails should we serve?"
#   - 5 cocktail options with CocktailDB data:
#     * Margarita, Mojito, Old Fashioned, Cosmopolitan, Piña Colada
#   - Each option includes: description, ingredients, image, external_id
#
# Test URL:
#   http://localhost:4000/{event-slug}/polls/{poll-number}
#   (URL is displayed after running)
#
# Test mobile view at 375px width to see line-clamp-2 optimization
#
# Usage:
#   mix run priv/repo/seeds/cocktail_poll_test.exs
#
# ============================================================================

alias EventasaurusApp.Repo
alias EventasaurusApp.Events.{Event, Poll, PollOption}
alias EventasaurusApp.Accounts.User
alias EventasaurusApp.Polls
import Ecto.Query

IO.puts("\n🍸 Creating cocktail poll test data...")

# Find the most recent event
event = Repo.one(from e in Event, where: is_nil(e.deleted_at), order_by: [desc: e.id], limit: 1)

unless event do
  IO.puts("❌ No events found!")
  exit(:shutdown)
end

IO.puts("✅ Using event: #{event.title} (#{event.slug})")

# Get first user for created_by_id
user = Repo.one(from u in User, order_by: [asc: u.id], limit: 1)

# Check if this event already has a cocktail poll
existing_poll = Repo.one(
  from p in Poll,
  where: p.event_id == ^event.id and p.poll_type == "cocktail",
  limit: 1
)

poll = if existing_poll do
  IO.puts("ℹ️  Event already has a cocktail poll (ID: #{existing_poll.id})")
  existing_poll
else
  # Create a cocktail poll

  poll_attrs = %{
    event_id: event.id,
    title: "What cocktails should we serve?",
    description: "Help us choose the best cocktails for our event! Vote for your favorites.",
    poll_type: "cocktail",
    voting_system: "star",
    phase: "voting_only",
    created_by_id: user.id,
    number: (Repo.one(from p in Poll, where: p.event_id == ^event.id, select: max(p.number)) || 0) + 1
  }

  changeset = Poll.changeset(%Poll{}, poll_attrs)

  case Repo.insert(changeset) do
    {:ok, created_poll} ->
      IO.puts("✅ Created cocktail poll (ID: #{created_poll.id})")
      created_poll
    {:error, changeset} ->
      IO.puts("❌ Failed to create cocktail poll:")
      IO.inspect(changeset.errors)
      exit(:shutdown)
  end
end

# Add some popular cocktails as options with real CocktailDB data
cocktails = [
  %{
    title: "Margarita",
    description: "Classic • Alcoholic\n\nServed in: Cocktail glass\n\nIngredients: 1 1/2 oz Tequila, 1/2 oz Triple sec, 1 oz Lime juice, Salt\n\nRub the rim of the glass with the lime slice to make the salt stick to it. Take care to moisten only the outer rim and sprinkle the salt on it. The salt should present to the lips of the imbiber and never mix into the cocktail. Shake the other ingredients with ice, then carefully pour into the glass.",
    external_id: "11007",
    image_url: "https://www.thecocktaildb.com/images/media/drink/5noda61589575158.jpg"
  },
  %{
    title: "Mojito",
    description: "Cocktail • Alcoholic\n\nServed in: Highball glass\n\nIngredients: 2-3 oz Light rum, 1 tbsp Sugar, 1 oz Lime juice, 2 oz Soda water, Mint\n\nMuddle mint leaves with sugar and lime juice. Add a splash of soda water and fill the glass with cracked ice. Pour the rum and top with soda water. Garnish and serve with straw.",
    external_id: "11000",
    image_url: "https://www.thecocktaildb.com/images/media/drink/metwgh1606770327.jpg"
  },
  %{
    title: "Old Fashioned",
    description: "Cocktail • Alcoholic\n\nServed in: Old-fashioned glass\n\nIngredients: 4.5 cL Bourbon, 2 dashes Angostura bitters, 1 cube Sugar, Few dashes Water\n\nPlace sugar cube in old fashioned glass and saturate with bitters, add a dash of plain water. Muddle until dissolved. Fill the glass with ice cubes and add whiskey. Garnish with orange twist, and a cocktail cherry.",
    external_id: "11001",
    image_url: "https://www.thecocktaildb.com/images/media/drink/vrwquq1478252802.jpg"
  },
  %{
    title: "Cosmopolitan",
    description: "Cocktail • Alcoholic\n\nServed in: Cocktail glass\n\nIngredients: 1 1/4 oz Vodka Citron, 1/2 oz Cointreau, 1/4 oz Lime juice, 1/2 oz Cranberry juice\n\nAdd all ingredients into cocktail shaker filled with ice. Shake well and double strain into large cocktail glass. Garnish with lime wheel.",
    external_id: "17196",
    image_url: "https://www.thecocktaildb.com/images/media/drink/kpsajh1504368362.jpg"
  },
  %{
    title: "Piña Colada",
    description: "Cocktail • Alcoholic\n\nServed in: Hurricane glass\n\nIngredients: 3 oz Light rum, 3 tbsp Coconut milk, 3 tbsp Crushed pineapple\n\nMix with crushed ice in blender until smooth. Pour into chilled glass, garnish and serve.",
    external_id: "17207",
    image_url: "https://www.thecocktaildb.com/images/media/drink/upgsue1668419912.jpg"
  }
]

# Add cocktail options
for cocktail <- cocktails do
  # Check if this option already exists
  existing_option = Repo.one(
    from po in PollOption,
    where: po.poll_id == ^poll.id and po.title == ^cocktail.title,
    limit: 1
  )

  unless existing_option do
    option_attrs = %{
      poll_id: poll.id,
      title: cocktail.title,
      description: cocktail.description,
      external_id: cocktail.external_id,
      external_data: %{
        "source" => "cocktaildb",
        "cocktail_id" => cocktail.external_id,
        "image_url" => cocktail.image_url
      },
      image_url: cocktail.image_url,
      suggested_by_id: user.id
    }

    changeset = PollOption.changeset(%PollOption{}, option_attrs)

    case Repo.insert(changeset) do
      {:ok, _option} ->
        IO.puts("  ✅ Added #{cocktail.title}")
      {:error, changeset} ->
        IO.puts("  ❌ Failed to add #{cocktail.title}:")
        IO.inspect(changeset.errors)
    end
  else
    IO.puts("  ℹ️  #{cocktail.title} already exists")
  end
end

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("🎉 Cocktail Poll Test Data Ready!")
IO.puts(String.duplicate("=", 70))
IO.puts("\n📋 Test URL:")
IO.puts("http://localhost:4000/#{event.slug}/polls/#{poll.number}")
IO.puts("\n✨ Poll has #{length(cocktails)} cocktail options with detailed descriptions")
IO.puts("Test the mobile view at 375px width to see the line-clamp-2 optimization!")
IO.puts("\n" <> String.duplicate("=", 70))
