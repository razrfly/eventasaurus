# Intelligent Event Aggregation: From Heuristic Classification to Predictive Analytics

## Abstract

This document describes the architectural evolution of an event aggregation platform from rule-based heuristic processing toward a modular AI pipeline with predictive capabilities. The system currently implements deterministic algorithms for multi-source data normalization, entity resolution, and categorical classification. The proposed enhancement introduces large language model (LLM) integration for content enrichment and autonomous source ingestion, culminating in a machine learning-based event demand prediction model optimized for sparse data environments.

The core innovation lies in the automated source acquisition pipeline: given a new event data source, the system autonomously analyzes the source structure, generates appropriate extraction logic, validates output quality, and integrates the source into the production pipeline—all within a defined convergence period without human intervention.

---

## 1. Current Infrastructure

### 1.1 System Architecture Overview

The platform operates on an Elixir/Phoenix stack with PostgreSQL (PostGIS-enabled) for persistence. Background job orchestration utilizes Oban, providing reliable job queuing with built-in retry mechanisms, job chaining, and observability.

**Core Components:**
- **Job Orchestration Layer**: Oban-based hierarchical job chains with parent-child relationships
- **Data Normalization Pipeline**: Multi-stage transformation from heterogeneous source formats to canonical schema
- **Entity Resolution System**: Fuzzy matching algorithms for venue, performer, and event deduplication
- **Category Taxonomy Engine**: Configurable mapping system with multi-source normalization
- **Monitoring Infrastructure**: Real-time job execution tracking with error categorization and performance baselines

### 1.2 Active Data Sources

The system currently ingests event data from 10+ heterogeneous sources:

| Source | Domain | Data Format | Update Frequency |
|--------|--------|-------------|------------------|
| Cinema City | Film/Cinema | REST API | Daily |
| Kino Kraków | Film/Cinema | HTML Scraping | Daily |
| Karnet | Cultural Events | HTML Scraping | Daily |
| Week.pl | Activities | REST API | Daily |
| Bandsintown | Music/Concerts | REST API | Hourly |
| Resident Advisor | Electronic Music | HTML Scraping | Daily |
| Sortiraparis | Cultural Events | HTML Scraping | Daily |
| Inquizition | Pub Quizzes | HTML Scraping | Weekly |
| Waw4Free | Free Events | HTML Scraping | Daily |
| Ticketmaster | Ticketed Events | REST API | Hourly |

Each source implements a standardized job hierarchy:
```
SyncJob (orchestration)
├── IndexPageJob (listing discovery)
├── EventDetailJob (detail extraction)
└── [Domain-specific jobs]
```

### 1.3 Heuristic Classification System

**Category Mapping Architecture:**

The system employs a configuration-driven taxonomy with YAML-defined mappings:

```yaml
# priv/category_mappings/{source}.yml
source_categories:
  "Koncert": "concerts"
  "Spektakl": "theater"
  "Wystawa": "exhibitions"
```

Multi-source normalization resolves heterogeneous categorization schemes (e.g., Ticketmaster's segment/genre/subgenre hierarchy, Karnet's Polish-language categories) to a canonical taxonomy.

**Matching Algorithms:**

1. **String Similarity**: Jaro-Winkler distance computation for fuzzy entity matching
   - Venue name reconciliation: threshold ≥ 0.85
   - Performer matching: threshold ≥ 0.80

2. **Geographic Proximity**: PostGIS-based spatial queries
   - Duplicate detection radius: 500 meters
   - Venue consolidation radius: 100 meters

3. **Temporal Proximity**: Date-window matching for recurring events
   - Default window: ±1 day for same-venue events

4. **Confidence Scoring**: Weighted multi-factor scoring
   ```
   confidence = (title_sim * 0.35) + (venue_sim * 0.25) +
                (date_proximity * 0.25) + (category_match * 0.15)
   ```
   - Acceptance threshold: ≥ 0.80

### 1.4 Monitoring and Observability

**MetricsTracker Integration:**

All jobs integrate with a centralized metrics system tracking:
- Execution duration (P50, P95, P99 percentiles)
- Success/failure rates with error categorization
- Job chain analysis for cascade failure detection

**Error Taxonomy:**

Nine standardized error categories enable systematic failure analysis:
- `validation_error`: Missing/invalid required fields
- `geocoding_error`: Address resolution failures
- `venue_error`: Venue lookup/creation issues
- `performer_error`: Artist matching failures
- `category_error`: Categorization failures
- `duplicate_error`: Duplicate detection issues
- `network_error`: HTTP/API failures
- `data_quality_error`: Parsing/format issues
- `unknown_error`: Uncategorized failures

---

## 2. Phase I: Modular AI Pipeline Integration

### 2.1 Objective

Introduce LLM capabilities as modular components within the existing pipeline, enhancing content quality and classification accuracy while maintaining deterministic fallback paths.

### 2.2 LLM Integration Points

**2.2.1 Content Enrichment Service**

```elixir
defmodule EventasaurusDiscovery.AI.ContentEnricher do
  @moduledoc """
  LLM-powered content enhancement for event descriptions.
  Provider-agnostic interface supporting multiple backends.
  """

  @callback enrich_description(raw_description :: String.t(), context :: map()) ::
    {:ok, enhanced_description :: String.t()} | {:error, reason :: term()}

  @callback suggest_categories(event_data :: map()) ::
    {:ok, categories :: [String.t()]} | {:error, reason :: term()}

  @callback extract_entities(text :: String.t()) ::
    {:ok, entities :: map()} | {:error, reason :: term()}
end
```

**Supported Operations:**
- Description enhancement and normalization
- Multi-language translation with cultural adaptation
- Category inference from unstructured text
- Named entity extraction (venues, performers, dates)
- Duplicate detection assistance via semantic similarity

**2.2.2 Provider Abstraction Layer**

The system implements a provider-agnostic interface supporting multiple LLM backends:

| Provider | Use Case | Characteristics |
|----------|----------|-----------------|
| Anthropic Claude | Complex reasoning, long-form content | High accuracy, moderate latency |
| Google Vertex AI | Batch processing, embeddings | Scalable, cost-effective |
| OpenAI GPT | General-purpose, function calling | Broad capability, established |
| Local Models | Privacy-sensitive, low-latency | On-premise, no API costs |

**2.2.3 Fallback Architecture**

```
Request → LLM Provider → Success → Enhanced Output
              ↓ (failure/timeout)
         Fallback Provider → Success → Enhanced Output
              ↓ (failure/timeout)
         Heuristic Fallback → Deterministic Output
```

All AI-enhanced paths maintain deterministic fallbacks ensuring system reliability independent of external service availability.

### 2.3 Integration with Existing Pipeline

**Job Enhancement Pattern:**

```elixir
defmodule EventasaurusDiscovery.Sources.Example.Jobs.EventDetailJob do
  use Oban.Worker
  alias EventasaurusDiscovery.AI.ContentEnricher
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"url" => url}} = job) do
    with {:ok, raw_data} <- fetch_event_data(url),
         {:ok, base_event} <- transform_to_canonical(raw_data),
         {:ok, enriched_event} <- maybe_enrich_with_ai(base_event) do

      MetricsTracker.record_success(job, enriched_event.external_id)
      {:ok, enriched_event}
    else
      {:error, reason} ->
        MetricsTracker.record_failure(job, reason)
        {:error, reason}
    end
  end

  defp maybe_enrich_with_ai(event) do
    case ContentEnricher.enrich_description(event.description, %{
      category: event.category,
      locale: event.locale
    }) do
      {:ok, enhanced} -> {:ok, %{event | description: enhanced, ai_enhanced: true}}
      {:error, _} -> {:ok, event}  # Graceful fallback
    end
  end
end
```

---

## 3. Phase II: Autonomous Source Ingestion

### 3.1 Objective

Develop an AI-driven system capable of automatically discovering, analyzing, and integrating new event data sources with minimal human intervention.

### 3.2 Autonomous Scraper Generation Pipeline

**3.2.1 Source Analysis Agent**

Given a URL or API endpoint, the analysis agent:

1. **Structure Detection**: Identifies data format (HTML, JSON, XML, RSS)
2. **Schema Inference**: Maps source fields to canonical event schema
3. **Pagination Analysis**: Detects pagination patterns and boundaries
4. **Rate Limit Detection**: Identifies throttling behavior
5. **Authentication Requirements**: Determines auth mechanisms

**3.2.2 Code Generation Pipeline**

```
Source URL → Analysis Agent → Schema Mapping → Code Generator → Test Suite → Validation → Integration
     ↑                                                              ↓
     └──────────────────── Feedback Loop ───────────────────────────┘
```

**Generated Artifacts:**
- `client.ex`: HTTP client with rate limiting and retry logic
- `transformer.ex`: Data transformation to canonical schema
- `jobs/*.ex`: Oban job implementations
- `test/*.exs`: Automated test cases

**3.2.3 Convergence Criteria**

The system considers a source "production-ready" when:

| Metric | Threshold |
|--------|-----------|
| Schema mapping accuracy | ≥ 95% |
| Field extraction success | ≥ 98% |
| Duplicate detection precision | ≥ 90% |
| Category classification accuracy | ≥ 85% |
| Geocoding success rate | ≥ 90% |
| Test suite pass rate | 100% |

**3.2.4 Iterative Refinement**

```elixir
defmodule EventasaurusDiscovery.AI.SourceIntegrator do
  @max_iterations 10
  @convergence_threshold 0.95

  def integrate_source(source_url, opts \\ []) do
    iterate_until_convergence(source_url, 0, opts)
  end

  defp iterate_until_convergence(_, iteration, _) when iteration >= @max_iterations do
    {:error, :max_iterations_exceeded}
  end

  defp iterate_until_convergence(source_url, iteration, opts) do
    with {:ok, analysis} <- analyze_source(source_url),
         {:ok, generated_code} <- generate_scraper(analysis),
         {:ok, test_results} <- run_validation_suite(generated_code),
         {:ok, quality_score} <- calculate_quality_score(test_results) do

      if quality_score >= @convergence_threshold do
        {:ok, %{code: generated_code, score: quality_score, iterations: iteration + 1}}
      else
        feedback = generate_improvement_feedback(test_results)
        iterate_until_convergence(source_url, iteration + 1, [{:feedback, feedback} | opts])
      end
    end
  end
end
```

### 3.3 Human-in-the-Loop Safeguards

While the system targets autonomous operation, critical checkpoints require human approval:

1. **Source Eligibility**: Legal/licensing verification
2. **Schema Conflicts**: When canonical schema requires modification
3. **Quality Exceptions**: When convergence criteria cannot be met
4. **Production Promotion**: Final approval before live deployment

---

## 4. Phase III: Event Demand Prediction Model

### 4.1 Objective

Develop a machine learning model for predicting event demand, optimized for sparse data environments typical of event aggregation platforms.

### 4.2 Feature Engineering

**4.2.1 Temporal Features**
- Day of week, month, season
- Holiday proximity
- Historical demand patterns for similar events
- Lead time (days until event)

**4.2.2 Categorical Features**
- Event category hierarchy
- Venue type and capacity
- Performer popularity indicators
- Price tier

**4.2.3 Geographic Features**
- Venue location clustering
- Population density
- Competing event density
- Transportation accessibility scores

**4.2.4 Cross-Source Signals**
- Multi-source listing frequency
- Social media mention velocity
- Ticket availability across platforms
- Price variance across sources

**4.2.5 Derived Popularity Indicators**
- Scrape frequency as popularity proxy
- Source priority weighting
- Historical conversion rates by category

### 4.3 Model Architecture

**4.3.1 Sparse Data Optimization**

Event data presents unique challenges:
- Cold start for new events (no historical data)
- Long-tail distribution (few popular, many niche events)
- Temporal sparsity (events are point-in-time)

**Proposed Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Ensemble Prediction Model                     │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Collaborative │  │  Content-    │  │    Time Series       │  │
│  │  Filtering   │  │   Based      │  │     Component        │  │
│  │  (Similar    │  │  (Category/  │  │   (Seasonal +        │  │
│  │   Events)    │  │   Venue)     │  │    Trend)            │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│         │                 │                     │               │
│         └─────────────────┴─────────────────────┘               │
│                           │                                      │
│                    ┌──────▼──────┐                              │
│                    │   Stacking  │                              │
│                    │   Meta-     │                              │
│                    │   Learner   │                              │
│                    └──────┬──────┘                              │
│                           │                                      │
│                    ┌──────▼──────┐                              │
│                    │  Demand     │                              │
│                    │  Prediction │                              │
│                    └─────────────┘                              │
└─────────────────────────────────────────────────────────────────┘
```

**4.3.2 Cold Start Mitigation**

For events with no historical data:

1. **Category Prior**: Use category-level demand distributions
2. **Venue Prior**: Historical performance at the same venue
3. **Performer Prior**: Artist/performer popularity scores
4. **Similar Event Matching**: Find historically similar events via embedding similarity

### 4.4 Training Pipeline

**Data Collection:**
- Historical event data with outcome indicators
- Ticket sales data (where available)
- User engagement metrics
- External signals (weather, competing events)

**Model Training:**
```elixir
defmodule EventasaurusDiscovery.ML.DemandPredictor do
  @moduledoc """
  Event demand prediction using ensemble methods.
  Implements training, inference, and model versioning.
  """

  def train(training_data, opts \\ []) do
    features = extract_features(training_data)
    labels = extract_demand_labels(training_data)

    # Train component models
    cf_model = train_collaborative_filter(features, labels)
    cb_model = train_content_based(features, labels)
    ts_model = train_time_series(features, labels)

    # Train meta-learner
    meta_features = stack_predictions([cf_model, cb_model, ts_model], features)
    meta_model = train_meta_learner(meta_features, labels)

    %{
      collaborative: cf_model,
      content_based: cb_model,
      time_series: ts_model,
      meta_learner: meta_model,
      version: generate_version(),
      trained_at: DateTime.utc_now()
    }
  end

  def predict(model, event_features) do
    component_predictions = [
      predict_component(model.collaborative, event_features),
      predict_component(model.content_based, event_features),
      predict_component(model.time_series, event_features)
    ]

    predict_meta(model.meta_learner, component_predictions)
  end
end
```

### 4.5 Evaluation Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| MAE | < 15% | Mean Absolute Error for demand prediction |
| MAPE | < 20% | Mean Absolute Percentage Error |
| Coverage | ≥ 90% | Percentage of events with valid predictions |
| Cold Start Accuracy | ≥ 70% | Accuracy for new events (no history) |
| Category Precision | ≥ 80% | Demand ranking accuracy within categories |

---

## 5. Technical Architecture

### 5.1 System Integration Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Event Aggregation Platform                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌─────────────┐    ┌─────────────────────────────────────────────────────┐ │
│  │   Source    │    │              AI Services Layer                       │ │
│  │  Discovery  │───▶│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │ │
│  │   Agent     │    │  │   Content    │  │   Category   │  │  Demand   │ │ │
│  └─────────────┘    │  │   Enricher   │  │   Inference  │  │ Predictor │ │ │
│         │           │  └──────────────┘  └──────────────┘  └───────────┘ │ │
│         │           └─────────────────────────────────────────────────────┘ │
│         │                        │                                           │
│         ▼                        ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                      Data Processing Pipeline                            ││
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ ││
│  │  │  Scraper │  │Transform │  │  Dedup   │  │ Geocode  │  │ Persist  │ ││
│  │  │   Jobs   │─▶│  Stage   │─▶│  Stage   │─▶│  Stage   │─▶│  Stage   │ ││
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘ ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                     │                                        │
│                                     ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                         Storage Layer                                    ││
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  ││
│  │  │   PostgreSQL     │  │   Vector Store   │  │    Model Store       │  ││
│  │  │   (PostGIS)      │  │   (Embeddings)   │  │   (ML Artifacts)     │  ││
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                     │                                        │
│                                     ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                      Monitoring & Analytics                              ││
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  ││
│  │  │  MetricsTracker  │  │    Baselines     │  │   Error Analysis     │  ││
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 LLM Provider Configuration

```elixir
# config/config.exs
config :eventasaurus_discovery, :ai,
  providers: [
    %{
      name: :primary,
      module: EventasaurusDiscovery.AI.Providers.Anthropic,
      config: %{
        model: "claude-3-sonnet",
        max_tokens: 4096,
        timeout: 30_000
      }
    },
    %{
      name: :fallback,
      module: EventasaurusDiscovery.AI.Providers.Vertex,
      config: %{
        model: "gemini-pro",
        max_tokens: 4096,
        timeout: 30_000
      }
    }
  ],
  fallback_strategy: :cascade,
  cache_ttl: :timer.hours(24)
```

---

## 6. Implementation Roadmap

### Phase I: Modular AI Pipeline (Foundation)

| Milestone | Deliverable | Success Criteria |
|-----------|-------------|------------------|
| I.1 | Provider abstraction layer | Support ≥2 LLM providers |
| I.2 | Content enrichment service | 95% uptime with fallback |
| I.3 | Category inference integration | ≥85% classification accuracy |
| I.4 | Monitoring integration | Full observability for AI calls |

### Phase II: Autonomous Source Ingestion (Automation)

| Milestone | Deliverable | Success Criteria |
|-----------|-------------|------------------|
| II.1 | Source analysis agent | Accurate structure detection |
| II.2 | Code generation pipeline | Valid Elixir code generation |
| II.3 | Validation framework | Automated quality scoring |
| II.4 | Integration workflow | <24h source integration time |

### Phase III: Demand Prediction (Intelligence)

| Milestone | Deliverable | Success Criteria |
|-----------|-------------|------------------|
| III.1 | Feature engineering pipeline | Comprehensive feature set |
| III.2 | Model training infrastructure | Reproducible training |
| III.3 | Ensemble model implementation | MAE <15% |
| III.4 | Production deployment | Real-time predictions |

---

## 7. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| LLM provider unavailability | Medium | High | Multi-provider fallback, caching |
| Model accuracy degradation | Medium | Medium | Continuous monitoring, retraining triggers |
| Data quality issues | High | Medium | Validation gates, human review |
| Cold start prediction failures | High | Low | Category/venue priors, conservative defaults |
| Autonomous scraper errors | Medium | High | Staged rollout, human checkpoints |

---

## 8. Conclusion

This architecture represents an evolution from deterministic rule-based processing toward an intelligent event aggregation platform. The phased approach ensures:

1. **Incremental Value**: Each phase delivers standalone improvements
2. **Risk Management**: Fallback mechanisms preserve reliability
3. **Scalability**: Autonomous source ingestion enables rapid expansion
4. **Differentiation**: Demand prediction provides unique market insights

The system maintains the robustness of heuristic algorithms while augmenting capabilities through modular AI integration, culminating in predictive analytics optimized for the sparse data characteristics inherent to event aggregation domains.

---

## References

- Oban Documentation: Background job processing for Elixir
- PostGIS: Spatial database extension for PostgreSQL
- Jaro-Winkler Algorithm: String similarity measurement
- Ensemble Methods: Machine learning model combination techniques
