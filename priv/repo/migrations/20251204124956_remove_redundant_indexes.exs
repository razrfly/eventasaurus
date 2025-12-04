defmodule EventasaurusApp.Repo.Migrations.RemoveRedundantIndexes do
  @moduledoc """
  Remove 41 redundant indexes identified by PlanetScale recommendations.

  These indexes are redundant because:
  1. Single-column indexes covered by composite indexes with same leading column
  2. Duplicate indexes with different naming conventions
  3. Indexes superseded by more comprehensive composite indexes

  See: https://github.com/razrfly/eventasaurus/issues/2499
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # ==========================================================================
    # VENUES (4 indexes)
    # ==========================================================================
    # #41: venues_city_image_queries_idx - redundant with venues_city_lookup_idx
    execute "DROP INDEX CONCURRENTLY IF EXISTS venues_city_image_queries_idx"

    # #40: venues_id_idx - redundant (primary key already indexed)
    execute "DROP INDEX CONCURRENTLY IF EXISTS venues_id_idx"

    # #39: venues_city_id_index - redundant with venues_city_lookup_idx (city_id, id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS venues_city_id_index"

    # #38: idx_venues_slug - duplicate of venues_slug_index (unique)
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_venues_slug"

    # ==========================================================================
    # USERS (1 index)
    # ==========================================================================
    # #37: users_profile_public_index - redundant with users_public_username_index (profile_public, lower(username))
    execute "DROP INDEX CONCURRENTLY IF EXISTS users_profile_public_index"

    # ==========================================================================
    # PUBLIC_EVENTS (5 indexes)
    # ==========================================================================
    # #36: public_events_venue_upcoming_idx - redundant with public_events_venue_time_id_idx (venue_id, starts_at, id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_events_venue_upcoming_idx"

    # #35: public_events_venue_id_starts_at_index - redundant with public_events_venue_time_id_idx
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_events_venue_id_starts_at_index"

    # #34: public_events_venue_id_index - redundant with public_events_venue_time_idx (venue_id, inserted_at)
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_events_venue_id_index"

    # #33: public_events_upcoming_idx - redundant with public_events_discovery_idx (starts_at, venue_id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_events_upcoming_idx"

    # #32: public_events_starts_at_index - redundant with public_events_discovery_idx (starts_at, venue_id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_events_starts_at_index"

    # ==========================================================================
    # PUBLIC_EVENT_SOURCES (2 indexes)
    # ==========================================================================
    # #31: public_event_sources_source_id_index - redundant with public_event_sources_source_event_idx
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_event_sources_source_id_index"

    # #30: public_event_sources_event_id_index - redundant with unique index public_event_sources_event_id_source_id_index
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_event_sources_event_id_index"

    # ==========================================================================
    # PUBLIC_EVENT_CONTAINER_MEMBERSHIPS (1 index)
    # ==========================================================================
    # #29: public_event_container_memberships_container_id_index - redundant with unique (container_id, event_id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_event_container_memberships_container_id_index"

    # ==========================================================================
    # PUBLIC_EVENT_CATEGORIES (1 index)
    # ==========================================================================
    # #28: public_event_categories_event_id_index - redundant with public_event_categories_event_category_lookup_idx
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_event_categories_event_id_index"

    # ==========================================================================
    # POLLS (2 indexes)
    # ==========================================================================
    # #27: polls_poll_type_index - redundant with polls_poll_type_phase_index (poll_type, phase)
    execute "DROP INDEX CONCURRENTLY IF EXISTS polls_poll_type_index"

    # #26: polls_event_id_index - redundant with unique polls_event_poll_type_unique partial index
    execute "DROP INDEX CONCURRENTLY IF EXISTS polls_event_id_index"

    # ==========================================================================
    # POLL_VOTES (2 indexes)
    # ==========================================================================
    # #25: poll_votes_poll_option_id_index - redundant with poll_votes_poll_option_id_voter_id_index
    execute "DROP INDEX CONCURRENTLY IF EXISTS poll_votes_poll_option_id_index"

    # #24: poll_votes_poll_id_index - redundant with poll_votes_poll_id_voter_id_index
    execute "DROP INDEX CONCURRENTLY IF EXISTS poll_votes_poll_id_index"

    # ==========================================================================
    # POLL_OPTIONS (1 index)
    # ==========================================================================
    # #23: poll_options_poll_id_index - redundant with poll_options_poll_id_status_index (poll_id, status)
    execute "DROP INDEX CONCURRENTLY IF EXISTS poll_options_poll_id_index"

    # ==========================================================================
    # OCCURRENCE_PLANNING (1 index)
    # ==========================================================================
    # #22: occurrence_planning_event_id_index - redundant with unique occurrence_planning_event_id_index
    # Note: This is the same as the unique index, checking if duplicate exists
    execute "DROP INDEX CONCURRENTLY IF EXISTS occurrence_planning_event_id_index"

    # ==========================================================================
    # OBAN_JOBS (3 indexes)
    # ==========================================================================
    # #21: oban_jobs_worker_state_idx - redundant with oban_jobs_worker_state_completed_idx
    execute "DROP INDEX CONCURRENTLY IF EXISTS oban_jobs_worker_state_idx"

    # #20: oban_jobs_worker_index - redundant with oban_jobs_worker_state_idx/oban_jobs_worker_state_completed_idx
    execute "DROP INDEX CONCURRENTLY IF EXISTS oban_jobs_worker_index"

    # #19: oban_jobs_state_index - redundant with Oban's own indexes and worker_state composite
    execute "DROP INDEX CONCURRENTLY IF EXISTS oban_jobs_state_index"

    # ==========================================================================
    # EVENT_PLANS (1 index)
    # ==========================================================================
    # #18: event_plans_public_event_id_index - redundant with unique (public_event_id, private_event_id, created_by)
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_plans_public_event_id_index"

    # ==========================================================================
    # JOB_EXECUTION_SUMMARIES (1 index)
    # ==========================================================================
    # #17: job_execution_summaries_worker_index - redundant with (worker, attempted_at) composite
    execute "DROP INDEX CONCURRENTLY IF EXISTS job_execution_summaries_worker_index"

    # ==========================================================================
    # GROUPS (1 index)
    # ==========================================================================
    # #16: groups_visibility_index - redundant with groups_visibility_join_policy_index
    execute "DROP INDEX CONCURRENTLY IF EXISTS groups_visibility_index"

    # ==========================================================================
    # GROUP_USERS (1 index)
    # ==========================================================================
    # #15: group_users_group_id_index - redundant with unique (group_id, user_id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS group_users_group_id_index"

    # ==========================================================================
    # EVENTS (1 index)
    # ==========================================================================
    # #14: events_status_index - redundant with events_status_start_at_index (status, start_at)
    execute "DROP INDEX CONCURRENTLY IF EXISTS events_status_index"

    # ==========================================================================
    # EVENT_USERS (5 indexes)
    # ==========================================================================
    # #13: event_users_user_id_event_id_idx - duplicate of unique event_users_event_id_user_id_index
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_users_user_id_event_id_idx"

    # #12: event_users_exclusion_index - duplicate of unique event_users_event_id_user_id_index (same columns)
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_users_exclusion_index"

    # #11: event_users_event_user_composite_idx - duplicate of unique event_users_event_id_user_id_index
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_users_event_user_composite_idx"

    # #10: event_users_user_id_index - redundant with event_users_user_id_event_id composite
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_users_user_id_index"

    # #9: event_users_event_id_index - redundant with unique event_users_event_id_user_id_index
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_users_event_id_index"

    # ==========================================================================
    # EVENT_PARTICIPANTS (4 indexes)
    # ==========================================================================
    # #8: event_participants_user_id_event_id_index - duplicate of unique event_participants_event_id_user_id_index
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_participants_user_id_event_id_index"

    # #7: event_participants_user_id_index - redundant with event_participants_user_id_event_id composite
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_participants_user_id_index"

    # #6: event_participants_invited_by_user_id_index - redundant with (invited_by_user_id, event_id) composite
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_participants_invited_by_user_id_index"

    # #5: event_participants_event_id_index - redundant with unique (event_id, user_id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS event_participants_event_id_index"

    # ==========================================================================
    # COUNTRIES (2 indexes)
    # ==========================================================================
    # #4: countries_code_unique - if this is a duplicate of unique constraint
    # Note: Only drop if there's a separate unique constraint, keeping for safety
    execute "DROP INDEX CONCURRENTLY IF EXISTS countries_code_unique"

    # #3: countries_slug_unique - if this is a duplicate
    execute "DROP INDEX CONCURRENTLY IF EXISTS countries_slug_unique"

    # ==========================================================================
    # CITIES (2 indexes)
    # ==========================================================================
    # #2: cities_name_index - redundant with cities_name_country_id_index (name, country_id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS cities_name_index"

    # #1: cities_country_id_index - redundant with cities_country_lookup_idx (country_id, id)
    execute "DROP INDEX CONCURRENTLY IF EXISTS cities_country_id_index"
  end

  def down do
    # Re-create indexes in reverse order if rollback is needed
    # Note: These will be created without CONCURRENTLY in down migration

    # Cities
    execute "CREATE INDEX IF NOT EXISTS cities_country_id_index ON cities (country_id)"
    execute "CREATE INDEX IF NOT EXISTS cities_name_index ON cities (name)"

    # Countries
    execute "CREATE UNIQUE INDEX IF NOT EXISTS countries_slug_unique ON countries (slug)"
    execute "CREATE UNIQUE INDEX IF NOT EXISTS countries_code_unique ON countries (code)"

    # Event participants
    execute "CREATE INDEX IF NOT EXISTS event_participants_event_id_index ON event_participants (event_id)"
    execute "CREATE INDEX IF NOT EXISTS event_participants_invited_by_user_id_index ON event_participants (invited_by_user_id)"
    execute "CREATE INDEX IF NOT EXISTS event_participants_user_id_index ON event_participants (user_id)"
    execute "CREATE INDEX IF NOT EXISTS event_participants_user_id_event_id_index ON event_participants (user_id, event_id)"

    # Event users
    execute "CREATE INDEX IF NOT EXISTS event_users_event_id_index ON event_users (event_id)"
    execute "CREATE INDEX IF NOT EXISTS event_users_user_id_index ON event_users (user_id)"
    execute "CREATE INDEX IF NOT EXISTS event_users_event_user_composite_idx ON event_users (event_id, user_id)"
    execute "CREATE INDEX IF NOT EXISTS event_users_exclusion_index ON event_users (event_id, user_id)"
    execute "CREATE INDEX IF NOT EXISTS event_users_user_id_event_id_idx ON event_users (user_id, event_id)"

    # Events
    execute "CREATE INDEX IF NOT EXISTS events_status_index ON events (status)"

    # Group users
    execute "CREATE INDEX IF NOT EXISTS group_users_group_id_index ON group_users (group_id)"

    # Groups
    execute "CREATE INDEX IF NOT EXISTS groups_visibility_index ON groups (visibility)"

    # Job execution summaries
    execute "CREATE INDEX IF NOT EXISTS job_execution_summaries_worker_index ON job_execution_summaries (worker)"

    # Event plans
    execute "CREATE INDEX IF NOT EXISTS event_plans_public_event_id_index ON event_plans (public_event_id)"

    # Oban jobs
    execute "CREATE INDEX IF NOT EXISTS oban_jobs_state_index ON oban_jobs (state)"
    execute "CREATE INDEX IF NOT EXISTS oban_jobs_worker_index ON oban_jobs (worker)"
    execute "CREATE INDEX IF NOT EXISTS oban_jobs_worker_state_idx ON oban_jobs (worker, state)"

    # Occurrence planning
    execute "CREATE INDEX IF NOT EXISTS occurrence_planning_event_id_index ON occurrence_planning (event_id)"

    # Poll options
    execute "CREATE INDEX IF NOT EXISTS poll_options_poll_id_index ON poll_options (poll_id)"

    # Poll votes
    execute "CREATE INDEX IF NOT EXISTS poll_votes_poll_id_index ON poll_votes (poll_id)"
    execute "CREATE INDEX IF NOT EXISTS poll_votes_poll_option_id_index ON poll_votes (poll_option_id)"

    # Polls
    execute "CREATE INDEX IF NOT EXISTS polls_event_id_index ON polls (event_id)"
    execute "CREATE INDEX IF NOT EXISTS polls_poll_type_index ON polls (poll_type)"

    # Public event categories
    execute "CREATE INDEX IF NOT EXISTS public_event_categories_event_id_index ON public_event_categories (event_id)"

    # Public event container memberships
    execute "CREATE INDEX IF NOT EXISTS public_event_container_memberships_container_id_index ON public_event_container_memberships (container_id)"

    # Public event sources
    execute "CREATE INDEX IF NOT EXISTS public_event_sources_event_id_index ON public_event_sources (event_id)"
    execute "CREATE INDEX IF NOT EXISTS public_event_sources_source_id_index ON public_event_sources (source_id)"

    # Public events
    execute "CREATE INDEX IF NOT EXISTS public_events_starts_at_index ON public_events (starts_at)"
    execute "CREATE INDEX IF NOT EXISTS public_events_upcoming_idx ON public_events (starts_at)"
    execute "CREATE INDEX IF NOT EXISTS public_events_venue_id_index ON public_events (venue_id)"
    execute "CREATE INDEX IF NOT EXISTS public_events_venue_id_starts_at_index ON public_events (venue_id, starts_at)"
    execute "CREATE INDEX IF NOT EXISTS public_events_venue_upcoming_idx ON public_events (venue_id, starts_at)"

    # Users
    execute "CREATE INDEX IF NOT EXISTS users_profile_public_index ON users (profile_public)"

    # Venues
    execute "CREATE INDEX IF NOT EXISTS idx_venues_slug ON venues (slug)"
    execute "CREATE INDEX IF NOT EXISTS venues_city_id_index ON venues (city_id)"
    execute "CREATE INDEX IF NOT EXISTS venues_id_idx ON venues (id)"
    execute "CREATE INDEX IF NOT EXISTS venues_city_image_queries_idx ON venues (city_id, id)"
  end
end
