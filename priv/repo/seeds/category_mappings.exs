# Seed initial category mappings for external sources
alias EventasaurusDiscovery.Categories

# Ensure the Categories context is available
Code.ensure_loaded(EventasaurusDiscovery.Categories)

# Seed initial mappings
EventasaurusDiscovery.Categories.seed_initial_mappings()

IO.puts("✅ Category mappings seeded successfully!")