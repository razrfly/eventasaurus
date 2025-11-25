# Database Separation & Scaling Strategy

## Problem Statement

We're experiencing production outages and performance degradation caused by OBAN background jobs competing with user-facing queries for database resources. While we've mitigated this partially by scheduling jobs during early morning hours (midnight-3am UTC), this is a band-aid solution that doesn't address the fundamental architecture issues.

**Key Issues:**
1. **Resource Contention**: ~60 concurrent OBAN workers sharing database connections with user-facing queries
2. **Supabase Limitations**: Hitting hard-coded connection pool limits and other constraints
3. **Reliability Risk**: Background job load causing outages for end users
4. **Scalability Concerns**: Current architecture won't scale as we add more users and data

## Current Architecture

### Database Setup
- **Provider**: Supabase Postgres with connection pooling (pgbouncer/Supavisor)
- **Connection Types**:
  - Transaction mode pooler (`SUPABASE_DATABASE_URL` port 6543) for user queries → `Repo` (pool_size: 5)
  - Session mode direct (`SUPABASE_SESSION_DATABASE_URL` port 5432) for OBAN → `SessionRepo` (pool_size: 5)
- **Infrastructure**: Fly.io (1GB RAM, 1 CPU shared, Frankfurt region)

### OBAN Configuration
- **Total Concurrent Workers**: ~60 across 20+ queues
- **Queue Breakdown**:
  - `scraper`: 5 workers
  - `scraper_detail`: 10 workers
  - `scraper_index`: 2 workers
  - `discovery`: 3 workers
  - `week_pl_detail`: 3 workers
  - `default`: 10 workers
  - Plus 15+ other specialized queues (emails, maintenance, reports, etc.)
- **Cron Jobs**: 4 daily scheduled jobs (midnight-3am UTC)

### Connection Pool Math Problem

**Current State:**
- OBAN workers: 60 concurrent
- SessionRepo pool: 5 connections
- **Problem**: 60 workers competing for 5 connections = severe bottleneck

**Supabase Constraints (Research Finding):**
- Pool sizes are **hard-coded per compute tier** and cannot be changed without upgrading
- Session mode (port 5432) and transaction mode (port 6543) **share the same pool size**
- Free tier: 60 max connections
- Pro tier: 90+ connections
- Recommended usage: 40-80% for pooler (leaving room for auth, admin utilities)
- Allowing too many direct connections can overwhelm Postgres schedulers

## Research Findings

### Supabase Connection Management

Supabase uses Supavisor as their connection pooler, with connection limits tied to compute tier:

- **Two Connection Types**:
  - Client connections: How many clients can connect to pooler (capped by compute tier)
  - Backend connections: Active connections pooler opens to Postgres (shared pool)
- **Connection Modes**:
  - Session mode (port 5432): For persistent clients like OBAN
  - Transaction mode (port 6543): For serverless/edge functions
- **Critical Limitation**: Connection limits are **hard-coded** and require compute upgrade to increase

**Best Practices:**
- Don't exceed 40% of pool for PostgREST API usage (leaves room for auth/utilities)
- For other workloads, can commit 80% to pool
- Start with `connection_limit=1` in serverless environments and gradually increase

**Sources:**
- [Supabase Connection Management Docs](https://supabase.com/docs/guides/database/connection-management)
- [Supavisor FAQ](https://supabase.com/docs/guides/troubleshooting/supavisor-faq-YyP5tI)
- [How to Change Max Database Connections](https://supabase.com/docs/guides/troubleshooting/how-to-change-max-database-connections-_BQ8P5)

### PlanetScale vs Supabase Comparison

#### PlanetScale Advantages

**Built-in High Availability:**
- Production tiers include **3-node cluster** (1 primary + 2 replicas) by default
- Replicas handle read queries and provide high availability
- Starts at **$34/month** for Scaler Pro (10GB across 3 nodes)
- Additional storage: $0.50/GB per instance (minimum 3 instances for production)

**Read Replica Architecture:**
- OLTP workloads are typically **80%+ reads**
- Read replicas included by default (no 3x cost multiplier)
- Better suited for read-heavy production workloads

**Advanced Features:**
- Non-blocking schema changes (Vitess-based)
- Horizontal sharding capabilities
- Built for large-scale applications

#### Supabase Considerations

**Read Replica Costs:**
- To match PlanetScale's 3-node HA setup, must add 2 replicas
- Cost becomes **3x the single-node configuration**
- Replicas not included by default

**Advantages:**
- Full PostgreSQL feature access (native Postgres, not Vitess)
- Integrated features: Auth, Storage, Realtime subscriptions
- Better for apps heavily using these integrations

**Large Deployments:**
- May require additional planning for horizontal scaling
- Read replicas or sharding needed for extreme scale

**Sources:**
- [PlanetScale vs Supabase Benchmarks](https://planetscale.com/benchmarks/supabase)
- [Supabase vs PlanetScale Comparison 2025](https://www.leanware.co/insights/supabase-vs-planetscale)
- [Supabase vs PlanetScale on Restack](https://www.restack.io/docs/supabase-knowledge-supabase-vs-planetscale)

### Fly.io + OBAN Patterns

**Official Example:**
- GitHub repo: [fly-apps/oban_example](https://github.com/fly-apps/oban_example)
- Demonstrates "Oban running in a global cluster with some read replicas"

**Multi-Region Architecture:**
- Fly.io supports read replicas in multiple regions
- Use `fly-replay` header to route writes to primary region
- Regional read replicas reduce latency

**Separate Database Pattern:**
- Fly Postgres deployed as separate app
- Can run multiple Postgres apps for different purposes
- Attach volumes for persistence

**Sources:**
- [Fly.io Multi-Region Database Guide](https://fly.io/docs/blueprints/multi-region-fly-replay/)
- [Fly.io High Availability & Global Replication](https://fly.io/docs/postgres/advanced-guides/high-availability-and-global-replication/)
- [Fly.io Community: Oban in Distributed Application](https://community.fly.io/t/oban-on-fly-io-in-a-distributed-application/7608)

### Ecto Read Replicas

**Built-in Support:**
- Ecto provides native support for primary and replica databases
- Configure multiple repositories in supervision tree
- Use `default_dynamic_repo` and `read_only: true` for replicas

**Implementation Pattern:**
```elixir
# Define primary and replica repos
defmodule MyApp.Repo, do: use Ecto.Repo
defmodule MyApp.ReplicaRepo, do: use Ecto.Repo

# Route reads to replica
MyApp.ReplicaRepo.all(query)
```

**Tools:**
- **EctoFacade**: Library for customizing read vs write repository routing
- Configurable selection algorithms for replica routing

**Sources:**
- [Ecto Replicas Guide (Official)](https://hexdocs.pm/ecto/replicas-and-dynamic-repositories.html)
- [Gigalixir Read Replicas Guide](https://www.gigalixir.com/docs/database/read-replicas)
- [Elixir Forum: Read/Write Replica Strategies](https://elixirforum.com/t/ecto-phoenix-strategies-for-dealing-with-read-write-from-replicas-primary-dbs/57861)

### Oban Database Isolation

**Isolation Strategies:**

1. **PostgreSQL Schema Prefixes**
   - Use Postgres schemas (Ecto "prefixes") for namespacing
   - Multiple Oban instances with separate job tables
   - Configure prefix in migrations and Oban config

2. **Multiple Oban Instances**
   - Run multiple Oban supervisors with different prefixes
   - Completely isolated job tables and notifications
   - Requires distinct supervisor names

3. **Separate Database**
   - Point Oban to entirely different database
   - Complete isolation from application data
   - Independent scaling and resource allocation

4. **Dynamic Repositories**
   - Support for Ecto dynamic repos via `:get_dynamic_repo` option
   - Separate Oban instance per dynamic repo

**Best Practice Note:**
"Some teams split the Oban database from the regular application database, though having two separate relational databases will solve some problems but will reintroduce others."

**Source:**
- [Oban Instance and Database Isolation (Official)](https://hexdocs.pm/oban/isolation.html)

## Solution Options

### Option 1: Optimize Within Supabase (Immediate/Low Effort)

**Approach:**
- Increase pool sizes for both Repo and SessionRepo
- Upgrade Supabase compute tier if needed
- Implement query timeout optimizations
- Add query performance monitoring

**Implementation:**
```elixir
# config/runtime.exs
config :eventasaurus, EventasaurusApp.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
  queue_target: 2000,  # Reduce from 5000ms
  queue_interval: 10000

config :eventasaurus, EventasaurusApp.SessionRepo,
  pool_size: String.to_integer(System.get_env("SESSION_POOL_SIZE") || "30")
```

**Pros:**
- ✅ Quick to implement (configuration change only)
- ✅ No migration effort
- ✅ Leverages existing Supabase features (auth, storage, realtime)
- ✅ Low cost (may need compute tier upgrade)

**Cons:**
- ❌ Doesn't solve fundamental resource sharing issue
- ❌ Still hitting hard-coded connection limits
- ❌ Vertical scaling only (no horizontal scaling)
- ❌ OBAN still competes with user queries

**Cost:**
- Supabase Pro compute upgrade: ~$25-50/month depending on tier

**Recommendation:** Do this immediately as a stop-gap, but plan for better isolation.

---

### Option 2: Separate OBAN Database (Medium Effort) ⭐ RECOMMENDED

**Approach:**
- Create dedicated Fly Postgres app for OBAN
- Move SessionRepo to point to OBAN database
- Keep user-facing queries on Supabase
- Migrate `oban_jobs`, `oban_peers`, and monitoring tables to OBAN DB

**Implementation Steps:**

1. **Create Fly Postgres App:**
```bash
# Create new Postgres app for OBAN
fly postgres create --name eventasaurus-oban-db --region fra --vm-size shared-cpu-1x --volume-size 10

# Get connection string
fly postgres connect -a eventasaurus-oban-db
```

2. **Update Configuration:**
```elixir
# config/runtime.exs
config :eventasaurus, EventasaurusApp.SessionRepo,
  url: System.get_env("OBAN_DATABASE_URL"),  # New Fly Postgres
  pool_size: 30,  # Can increase without Supabase limits
  queue_target: 2000,
  queue_interval: 10000

config :eventasaurus, Oban,
  repo: EventasaurusApp.SessionRepo,
  # ... existing queues
```

3. **Migrate OBAN Tables:**
```bash
# Run Oban migrations against new database
OBAN_DATABASE_URL=<fly-postgres-url> mix ecto.migrate -r EventasaurusApp.SessionRepo

# Optionally migrate monitoring tables (job_execution_summaries)
```

4. **Update Fly.io Secrets:**
```bash
fly secrets set OBAN_DATABASE_URL="postgres://..."
```

**Pros:**
- ✅ **Complete isolation** of OBAN load from user queries
- ✅ Independent scaling for each workload
- ✅ No Supabase connection limit concerns for OBAN
- ✅ Can optimize each database for its workload
- ✅ Supabase features (auth, storage) still available for user data
- ✅ Foundation for future read replica addition

**Cons:**
- ❌ Two databases to manage and monitor
- ❌ Cross-database queries not possible (but likely not needed)
- ❌ Need to handle two backup strategies
- ❌ Increased operational complexity

**Cost:**
- Fly Postgres (shared-cpu-1x, 10GB): **~$5-10/month**
- Keep existing Supabase plan
- **Total additional cost: ~$10/month**

**Migration Risks:**
- Need to handle zero-downtime migration of OBAN jobs table
- Testing in staging environment critical
- Ensure monitoring tables migrate correctly

**Why This is Recommended:**
- Best balance of isolation vs complexity
- Lowest additional cost (~$10/month)
- Immediate relief for user-facing queries
- No loss of Supabase features
- Can add read replicas later if needed

---

### Option 3: Add Read Replicas on Supabase (Medium-High Cost)

**Approach:**
- Add 2 read replicas to Supabase
- Configure Ecto to route read queries to replicas
- Keep writes on primary
- Implement EctoFacade or custom routing logic

**Implementation:**
```elixir
# Define replica repos
defmodule EventasaurusApp.ReplicaRepo do
  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end

# Route reads to replica
def list_events do
  EventasaurusApp.ReplicaRepo.all(Event)
end
```

**Pros:**
- ✅ Scales read capacity significantly
- ✅ Stays on Supabase (familiar platform)
- ✅ Reduces load on primary database
- ✅ Native Ecto support for replicas

**Cons:**
- ❌ **Expensive**: 3x Supabase cost (primary + 2 replicas)
- ❌ OBAN writes still compete with user writes on primary
- ❌ Still limited by primary's connection pool for writes
- ❌ Replication lag considerations
- ❌ Doesn't solve OBAN isolation problem

**Cost:**
- If current Supabase: $25/month → 3x = **$75/month additional**
- Total: ~$100/month for database alone

**Recommendation:** Only pursue if read performance becomes critical AND Option 2 already implemented.

---

### Option 4: Migrate to PlanetScale (High Effort)

**Approach:**
- Full migration from Supabase to PlanetScale
- Leverage included 3-node cluster (1 primary + 2 replicas)
- Use Vitess connection pooling
- Migrate auth/storage to separate services

**Implementation Challenges:**
- Migrate from native Postgres to Vitess (connection semantics differ)
- Replace Supabase Auth (Auth0, Clerk, or custom)
- Replace Supabase Storage (S3, R2, or other)
- Replace Supabase Realtime (Phoenix Channels, Ably, or custom)
- Update all database queries for Vitess compatibility
- Schema migration from Postgres to MySQL-compatible format

**Pros:**
- ✅ Built-in 3-node HA cluster (included in base price)
- ✅ Better cost for read-heavy workloads (2 replicas included)
- ✅ Non-blocking schema changes
- ✅ Horizontal sharding capabilities
- ✅ Optimized for large-scale OLTP

**Cons:**
- ❌ **Major migration effort** (weeks-months)
- ❌ Lose Supabase integrated features (auth, storage, realtime)
- ❌ Vitess has different connection semantics than Postgres
- ❌ Need to replace/migrate authentication system
- ❌ Need to replace file storage system
- ❌ Testing and validation complexity
- ❌ Risk of downtime during migration

**Cost:**
- PlanetScale Scaler Pro: $34/month (10GB, 3 nodes)
- Auth replacement: $25-100/month (Auth0, Clerk)
- Storage replacement: $5-20/month (S3, R2)
- **Total: ~$65-155/month** (vs current ~$25-50 for Supabase)

**Recommendation:** Only consider if:
1. Read performance becomes critical bottleneck after other options exhausted
2. Need horizontal sharding for massive scale
3. Have engineering resources for multi-week migration project
4. Willing to replace Supabase integrated features

---

### Option 5: Hybrid Architecture (Best Long-term, Highest Complexity)

**Approach:**
- Move OBAN to dedicated Fly Postgres (Option 2)
- Keep Supabase for user data
- Add read replicas (either Supabase or Fly Postgres) for read-heavy tables
- Implement Ecto multi-repo routing strategy

**Architecture:**
```
┌─────────────────────────────────────────┐
│           Application Layer              │
└────┬──────────────┬──────────────┬──────┘
     │              │              │
     ▼              ▼              ▼
┌─────────┐   ┌──────────┐   ┌──────────┐
│ Supabase│   │ Fly PG   │   │ Read     │
│ Primary │   │ (OBAN)   │   │ Replicas │
│         │   │          │   │          │
│ Users   │   │ oban_    │   │ Events   │
│ Auth    │   │ jobs     │   │ Venues   │
│ Storage │   │ oban_    │   │ (reads)  │
│         │   │ peers    │   │          │
└─────────┘   └──────────┘   └──────────┘
```

**Implementation:**
1. Implement Option 2 first (separate OBAN database)
2. Monitor read vs write workload patterns
3. If reads become bottleneck, add read replicas:
   - Option A: Supabase replicas for auth-related reads
   - Option B: Fly Postgres replicas for event/venue reads
4. Implement EctoFacade for automatic read/write routing

**Pros:**
- ✅ **Maximum isolation** and scalability
- ✅ Optimize each database for its workload
- ✅ Flexible read replica placement
- ✅ Best performance for all workload types
- ✅ Can scale each component independently

**Cons:**
- ❌ **Most complex** operational setup
- ❌ Three+ databases to manage
- ❌ Multiple backup/monitoring strategies
- ❌ Cross-database query limitations
- ❌ Highest operational overhead

**Cost:**
- Fly Postgres (OBAN): $10/month
- Supabase (primary): $25-50/month
- Read replicas: $25-100/month (depending on implementation)
- **Total: ~$60-160/month**

**Recommendation:** Only pursue after implementing Option 2 and confirming read performance is still a bottleneck.

## Recommended Implementation Path

### Phase 1: Immediate (This Week) - Option 1
**Goal:** Stop the bleeding, buy time for proper solution

1. **Increase Pool Sizes:**
   ```elixir
   # config/runtime.exs
   pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15")
   session_pool_size: String.to_integer(System.get_env("SESSION_POOL_SIZE") || "20")
   ```

2. **Check Supabase Compute Tier:**
   - Review current tier's connection limits
   - Upgrade if we're at ceiling

3. **Add Connection Pool Monitoring:**
   - Add Telemetry for pool checkout times
   - Set up alerts for pool exhaustion

4. **Deploy & Monitor:**
   - Deploy changes to production
   - Monitor for 1-2 weeks
   - Track outage frequency

**Expected Outcome:** Reduce outage frequency but not eliminate root cause.

---

### Phase 2: Short-term (Next 2-4 Weeks) - Option 2 ⭐
**Goal:** Isolate OBAN from user queries completely

1. **Staging Environment Setup:**
   ```bash
   # Create staging OBAN database
   fly postgres create --name eventasaurus-oban-db-staging --region fra
   ```

2. **Migration Script Development:**
   - Write zero-downtime migration for OBAN tables
   - Include rollback procedures
   - Test in staging thoroughly

3. **Production Migration:**
   - Schedule maintenance window (or go zero-downtime)
   - Migrate OBAN tables to Fly Postgres
   - Update SessionRepo configuration
   - Deploy application changes
   - Monitor for 48 hours intensively

4. **Validation:**
   - Verify OBAN jobs running normally
   - Check user query performance
   - Monitor connection pool usage on both databases
   - Confirm zero cross-database query issues

**Expected Outcome:** User queries completely isolated from OBAN load. Outages should stop.

**Estimated Effort:** 3-5 days development/testing, 2-4 hours production migration

---

### Phase 3: Medium-term (2-3 Months) - Evaluate Need for Replicas
**Goal:** Determine if read replicas needed

1. **Performance Monitoring:**
   - Collect 60 days of metrics post-OBAN migration
   - Analyze read vs write query patterns
   - Measure p95/p99 response times
   - Track peak load patterns

2. **Decision Point:**
   - **If read performance is good:** Stop here, Option 2 sufficient
   - **If read performance degrades:** Proceed to Phase 4

---

### Phase 4: Long-term (3-6 Months) - Add Read Replicas if Needed
**Goal:** Scale read capacity if Option 2 proves insufficient

1. **Read Workload Analysis:**
   - Identify most frequently read tables (events, venues, etc.)
   - Calculate read vs write ratio
   - Estimate replica benefit

2. **Implementation Choice:**
   - **Option A**: Supabase replicas if using auth/storage heavily
   - **Option B**: Fly Postgres replicas for event/venue reads
   - **Option C**: Hybrid (best but most complex)

3. **Implement Chosen Solution:**
   - Set up read replica infrastructure
   - Implement Ecto read/write routing
   - Test thoroughly in staging
   - Gradual rollout to production

**Expected Outcome:** Horizontal read scaling for continued growth.

## Cost Comparison Summary

| Solution | Setup Cost | Monthly Cost | Engineering Effort |
|----------|-----------|--------------|-------------------|
| **Option 1: Optimize Supabase** | $0 | +$25-50 | 1 day |
| **Option 2: Separate OBAN DB** ⭐ | $0 | +$10 | 3-5 days |
| **Option 3: Supabase Replicas** | $0 | +$75 | 1-2 weeks |
| **Option 4: Migrate PlanetScale** | $0 | $65-155 | 4-8 weeks |
| **Option 5: Hybrid** | $0 | $60-160 | 2-4 weeks |

**Current Baseline:** ~$25-50/month (Supabase Pro)

**Recommended Path Cost:**
- Phase 1 (Immediate): +$0-25/month
- Phase 2 (Short-term): +$10/month
- Phase 3-4 (If needed): +$25-100/month
- **Total: $35-185/month** (depending on whether replicas needed)

## Technical Implementation Details

### Separate OBAN Database (Option 2) - Detailed Steps

#### 1. Create Fly Postgres App

```bash
# Create Postgres app
fly postgres create \
  --name eventasaurus-oban-db \
  --region fra \
  --initial-cluster-size 1 \
  --vm-size shared-cpu-1x \
  --volume-size 10

# Attach to main app (creates DATABASE_URL secret)
fly postgres attach \
  --app eventasaurus \
  --postgres-app eventasaurus-oban-db \
  --variable-name OBAN_DATABASE_URL
```

#### 2. Update Application Configuration

```elixir
# config/runtime.exs

# Add new repo configuration for OBAN database
if config_env() == :prod do
  # Existing Repo stays on Supabase for user data
  config :eventasaurus, EventasaurusApp.Repo,
    url: System.get_env("SUPABASE_DATABASE_URL"),
    # ... existing config

  # SessionRepo now points to dedicated Fly Postgres for OBAN
  config :eventasaurus, EventasaurusApp.SessionRepo,
    url: System.get_env("OBAN_DATABASE_URL"),
    database: "postgres",
    pool_size: String.to_integer(System.get_env("OBAN_POOL_SIZE") || "30"),
    queue_target: 2000,
    queue_interval: 10000,
    connect_timeout: 30_000,
    handshake_timeout: 30_000,
    # Fly Postgres uses SSL by default
    ssl: true

  # Oban config stays the same (still uses SessionRepo)
  config :eventasaurus, Oban,
    repo: EventasaurusApp.SessionRepo,
    # ... existing queues
end
```

#### 3. Migration Strategy

**Option A: Zero-Downtime Migration (Recommended)**

```elixir
# 1. Deploy with dual writes (temporary)
defmodule DualWriteObanWorker do
  @moduledoc """
  Temporary worker that writes to both databases during migration.
  Remove after migration complete.
  """

  def insert_job(params) do
    # Write to both Supabase (old) and Fly Postgres (new)
    Multi.new()
    |> Multi.run(:old_db, fn _repo, _changes ->
      Repo.transaction(fn -> Oban.insert(params) end)
    end)
    |> Multi.run(:new_db, fn _repo, _changes ->
      SessionRepo.transaction(fn -> Oban.insert(params) end)
    end)
    |> Repo.transaction()
  end
end

# 2. Copy existing jobs from Supabase to Fly Postgres
# Run this as one-time data migration
mix run -e "EventasaurusApp.Migrations.CopyObanJobs.run()"

# 3. Switch reads to new database (feature flag)
config :eventasaurus, :oban_database, :fly_postgres

# 4. Stop dual writes, remove old OBAN tables from Supabase
```

**Option B: Maintenance Window Migration (Simpler)**

```bash
# 1. Put app in maintenance mode
fly scale count 0

# 2. Backup OBAN data from Supabase
pg_dump -h <supabase-host> -U postgres -t oban_jobs -t oban_peers > oban_backup.sql

# 3. Restore to Fly Postgres
psql $OBAN_DATABASE_URL < oban_backup.sql

# 4. Deploy new configuration
fly deploy

# 5. Scale back up
fly scale count 2
```

#### 4. Monitoring Tables Decision

**Should monitoring tables move to OBAN DB?**

Current monitoring tables:
- `job_execution_summaries` (tracks OBAN job performance)
- Other OBAN-related metrics

**Recommendation:**
- **Keep monitoring tables on Supabase (Repo)** for now
- Reasoning:
  - Admin dashboard queries join with other app data
  - Easier to query from main application
  - Lower query volume than OBAN jobs table
  - Can move later if needed

**Alternative:**
- Move to OBAN DB for complete isolation
- Requires updating all dashboard queries to use SessionRepo
- Pros: Complete separation
- Cons: Cross-database queries for dashboard

#### 5. Testing Checklist

Before production migration:

- [ ] OBAN jobs insert successfully to new database
- [ ] OBAN workers process jobs from new database
- [ ] Cron jobs trigger correctly
- [ ] Job monitoring/metrics still work
- [ ] No connection pool exhaustion on either database
- [ ] Admin dashboards load correctly
- [ ] Rollback procedure tested and documented
- [ ] Connection string securely stored in Fly.io secrets
- [ ] SSL certificate validation working
- [ ] Backup strategy configured for new database

#### 6. Rollback Plan

If migration fails:

```bash
# 1. Revert configuration
git revert <migration-commit>

# 2. Redeploy
fly deploy

# 3. Scale back up
fly scale count 2

# 4. Monitor
fly logs
```

Keep both databases for 7 days before removing old OBAN tables.

### Read Replica Implementation (Future Phase)

If pursuing read replicas later:

```elixir
# config/runtime.exs

# Define replica repo
config :eventasaurus, EventasaurusApp.ReplicaRepo,
  url: System.get_env("REPLICA_DATABASE_URL"),
  pool_size: 10,
  read_only: true

# Update supervision tree
def start(_type, _args) do
  children = [
    EventasaurusApp.Repo,
    EventasaurusApp.SessionRepo,
    EventasaurusApp.ReplicaRepo,  # Add replica
    # ... other children
  ]
end

# Implement read routing
defmodule EventasaurusApp.Events do
  # Writes go to primary
  def create_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  # Reads come from replica
  def list_events do
    ReplicaRepo.all(Event)
  end

  # Or use EctoFacade for automatic routing
  def get_event(id) do
    EctoFacade.one(Event, id)  # Auto-routes to replica
  end
end
```

## Migration Risks & Mitigation

### Risk 1: Data Loss During Migration
**Mitigation:**
- Full backup before migration
- Test migration process in staging
- Use zero-downtime migration strategy
- Keep both databases active for 7 days

### Risk 2: Connection String Leakage
**Mitigation:**
- Use Fly.io secrets, never commit connection strings
- Rotate credentials after migration
- Use SSL with certificate validation

### Risk 3: Cross-Database Query Failures
**Mitigation:**
- Audit codebase for joins between OBAN and app data
- Update queries to use appropriate repo
- Comprehensive test coverage

### Risk 4: Monitoring Gaps
**Mitigation:**
- Add telemetry for both databases
- Set up alerts for connection pool exhaustion
- Monitor query performance on both databases
- Track OBAN job success rates

### Risk 5: Increased Operational Complexity
**Mitigation:**
- Document backup procedures for both databases
- Automate monitoring/alerting
- Create runbooks for common issues
- Consider managed database options if team too small

## Success Metrics

### Phase 1 (Immediate)
- [ ] Outage frequency reduced by 50%
- [ ] Connection pool checkout time p95 < 100ms
- [ ] Zero connection pool exhaustion errors

### Phase 2 (Short-term)
- [ ] **Zero outages** caused by OBAN load
- [ ] User query p95 latency < 200ms
- [ ] OBAN job processing throughput maintained or improved
- [ ] Both connection pools < 80% utilization during peak

### Phase 3-4 (Long-term, if needed)
- [ ] Read query p95 < 100ms
- [ ] Support 10x user growth without performance degradation
- [ ] Database costs remain < $200/month

## Next Steps

1. **Immediate (This Week):**
   - [ ] Review this issue with team
   - [ ] Decide on Phase 1 implementation timeline
   - [ ] Implement Option 1 (increase pool sizes)
   - [ ] Set up connection pool monitoring

2. **Short-term (Next 2 Weeks):**
   - [ ] Create Fly Postgres staging database
   - [ ] Develop migration scripts for Option 2
   - [ ] Test in staging environment
   - [ ] Schedule production migration

3. **Medium-term (2-3 Months):**
   - [ ] Collect performance metrics post-migration
   - [ ] Evaluate need for read replicas
   - [ ] Make decision on Phase 4

## References

### Supabase Resources
- [Connection Management](https://supabase.com/docs/guides/database/connection-management)
- [Supavisor FAQ](https://supabase.com/docs/guides/troubleshooting/supavisor-faq-YyP5tI)
- [How to Change Max Database Connections](https://supabase.com/docs/guides/troubleshooting/how-to-change-max-database-connections-_BQ8P5)
- [Remaining Connection Slots Error](https://supabase.com/docs/guides/troubleshooting/database-error-remaining-connection-slots-are-reserved-for-non-replication-superuser-connections-3V3nIb)

### PlanetScale Resources
- [PlanetScale vs Supabase Benchmarks](https://planetscale.com/benchmarks/supabase)
- [Supabase vs PlanetScale Comparison 2025](https://www.leanware.co/insights/supabase-vs-planetscale)
- [Benchmarking Postgres](https://planetscale.com/blog/benchmarking-postgres)

### Fly.io Resources
- [Multi-Region Databases and fly-replay](https://fly.io/docs/blueprints/multi-region-fly-replay/)
- [High Availability & Global Replication](https://fly.io/docs/postgres/advanced-guides/high-availability-and-global-replication/)
- [Oban Example Repository](https://github.com/fly-apps/oban_example)
- [Multi-Region Database Guide](https://community.fly.io/t/multi-region-database-guide/1600)
- [Oban on Fly.io in Distributed Application](https://community.fly.io/t/oban-on-fly-io-in-a-distributed-application/7608)

### Ecto Resources
- [Ecto Replicas and Dynamic Repositories (Official)](https://hexdocs.pm/ecto/replicas-and-dynamic-repositories.html)
- [Using an Ecto Readonly Replica Repo](https://blog.swwomm.com/2021/01/using-ecto-readonly-replica-repo.html)
- [Gigalixir Read Replicas Guide](https://www.gigalixir.com/docs/database/read-replicas)
- [EctoFacade - Handling Multiple Ecto Repositories](https://medium.com/@bartoszlecki/ectofacade-handling-multiple-ecto-repositories-76cc456a2926)

### Oban Resources
- [Oban Instance and Database Isolation (Official)](https://hexdocs.pm/oban/isolation.html)
- [How Many Connections Does Oban Need?](https://elixirforum.com/t/how-many-connections-does-oban-need/55551)

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-01-25 | Research and document options | Need comprehensive analysis before making architectural changes |
| TBD | Choose implementation path | Pending team review and discussion |
| TBD | Begin Phase 1 implementation | TBD |

---

**Created:** 2025-01-25
**Status:** Research Complete, Pending Team Review
**Priority:** High
**Estimated Effort:** Phase 1: 1 day, Phase 2: 3-5 days
**Cost Impact:** +$10-60/month depending on chosen solution
