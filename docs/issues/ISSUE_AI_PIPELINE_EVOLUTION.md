# [RFC] Intelligent Event Aggregation: Modular AI Pipeline with Predictive Analytics

## Summary

Evolution of the event aggregation platform from rule-based heuristic processing toward a modular AI pipeline with autonomous source ingestion and event demand prediction capabilities.

## Motivation

The current system implements deterministic algorithms for multi-source data normalization, entity resolution, and categorical classification. While effective, this approach has inherent limitations:

1. **Manual source integration**: Each new data source requires significant development effort
2. **Static categorization**: Rule-based mapping cannot adapt to new patterns
3. **No predictive capability**: System is reactive rather than proactive
4. **Content quality variance**: Heterogeneous source quality without normalization

Introducing LLM integration enables content enrichment, autonomous source discovery, and ultimately predictive analytics for event demand.

## Current Infrastructure

### Data Pipeline Architecture

```
Sources (10+) → Oban Jobs → Transform → Dedup → Geocode → Persist
                    │
              MetricsTracker
                    │
            Error Categorization
```

### Existing Components

| Component | Implementation | Status |
|-----------|---------------|--------|
| Job Orchestration | Oban with hierarchical chains | Production |
| Category Mapping | YAML configuration | Production |
| String Matching | Jaro-Winkler algorithm | Production |
| Geo Matching | PostGIS proximity queries | Production |
| Confidence Scoring | Weighted multi-factor | Production |
| Error Tracking | 9-category taxonomy | Production |
| Performance Baselines | P50/P95/P99 tracking | Production |

### Active Sources

- Cinema City, Kino Kraków (Film)
- Karnet, Week.pl (Cultural)
- Bandsintown, Resident Advisor (Music)
- Sortiraparis (Cultural)
- Inquizition, PubQuiz (Entertainment)
- Ticketmaster (Ticketed Events)

## Proposed Enhancement

### Phase I: Modular AI Pipeline

**Objective**: Introduce LLM capabilities as modular components with deterministic fallbacks.

**Integration Points**:
- Content enrichment (description enhancement, translation)
- Category inference from unstructured text
- Entity extraction (venues, performers, dates)
- Semantic similarity for deduplication

**Provider Abstraction**:
```elixir
defmodule EventasaurusDiscovery.AI.ContentEnricher do
  @callback enrich_description(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  @callback suggest_categories(map()) :: {:ok, [String.t()]} | {:error, term()}
  @callback extract_entities(String.t()) :: {:ok, map()} | {:error, term()}
end
```

**Supported Providers**: Anthropic Claude, Google Vertex AI, OpenAI, Local Models

**Fallback Architecture**:
```
LLM Provider → Fallback Provider → Heuristic Fallback
```

### Phase II: Autonomous Source Ingestion

**Objective**: AI-driven system for automatic source discovery and integration.

**Pipeline**:
```
Source URL → Analysis Agent → Schema Mapping → Code Generator → Validation → Integration
                                                                    ↑
                                              Feedback Loop ─────────┘
```

**Generated Artifacts**:
- `client.ex`: HTTP client with rate limiting
- `transformer.ex`: Data transformation logic
- `jobs/*.ex`: Oban job implementations
- `test/*.exs`: Automated test cases

**Convergence Criteria**:
| Metric | Threshold |
|--------|-----------|
| Schema mapping accuracy | ≥95% |
| Field extraction success | ≥98% |
| Category classification | ≥85% |
| Test suite pass rate | 100% |

**Target**: <24h from source URL to production integration

### Phase III: Event Demand Prediction

**Objective**: ML model for predicting event demand, optimized for sparse data.

**Feature Categories**:
- Temporal (day, season, lead time)
- Categorical (event type, venue, performer)
- Geographic (location, density, accessibility)
- Cross-source (listing frequency, price variance)
- Derived (scrape frequency as popularity proxy)

**Model Architecture**:
```
┌─────────────────────────────────────────┐
│         Ensemble Prediction Model        │
├─────────────────────────────────────────┤
│  Collaborative │ Content-Based │ Time   │
│   Filtering    │               │ Series │
├─────────────────────────────────────────┤
│              Meta-Learner               │
├─────────────────────────────────────────┤
│           Demand Prediction             │
└─────────────────────────────────────────┘
```

**Cold Start Mitigation**:
- Category-level demand priors
- Venue historical performance
- Performer popularity scores
- Similar event embedding matching

**Target Metrics**:
| Metric | Target |
|--------|--------|
| MAE | <15% |
| Coverage | ≥90% |
| Cold Start Accuracy | ≥70% |

## Technical Approach

### Provider-Agnostic Design

The system abstracts LLM provider specifics behind a common interface:

```elixir
config :eventasaurus_discovery, :ai,
  providers: [
    %{name: :primary, module: AI.Providers.Anthropic},
    %{name: :fallback, module: AI.Providers.Vertex}
  ],
  fallback_strategy: :cascade
```

### Integration with Existing Jobs

```elixir
defp maybe_enrich_with_ai(event) do
  case ContentEnricher.enrich_description(event.description, context) do
    {:ok, enhanced} -> {:ok, %{event | description: enhanced, ai_enhanced: true}}
    {:error, _} -> {:ok, event}  # Graceful fallback to original
  end
end
```

### Monitoring Integration

All AI operations integrate with existing MetricsTracker:
- LLM call latency tracking
- Provider availability monitoring
- Fallback activation rates
- Content enhancement success rates

## Implementation Milestones

### Phase I (Foundation)
- [ ] Provider abstraction layer
- [ ] Content enrichment service
- [ ] Category inference integration
- [ ] Fallback mechanism implementation
- [ ] Monitoring integration

### Phase II (Automation)
- [ ] Source analysis agent
- [ ] Code generation pipeline
- [ ] Validation framework
- [ ] Iterative refinement loop
- [ ] Human-in-the-loop checkpoints

### Phase III (Intelligence)
- [ ] Feature engineering pipeline
- [ ] Training data collection
- [ ] Ensemble model implementation
- [ ] Cold start handling
- [ ] Production deployment

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Provider unavailability | Multi-provider fallback, response caching |
| Model accuracy drift | Continuous monitoring, retraining triggers |
| Autonomous scraper errors | Staged rollout, human review gates |
| Cold start failures | Conservative priors, category-level defaults |

## Success Criteria

**Phase I Complete When**:
- ≥2 LLM providers supported with automatic fallback
- Content enrichment achieving ≥85% category accuracy
- Zero degradation in pipeline reliability

**Phase II Complete When**:
- New source integration <24h from URL to production
- ≥90% of generated scrapers pass validation
- Human intervention required <10% of integrations

**Phase III Complete When**:
- Demand prediction MAE <15%
- Coverage ≥90% of events
- Cold start accuracy ≥70%

## Related Documentation

- [Full Technical Specification](./ai-pipeline-architecture.md)
- [Source Implementation Guide](../source-implementation-guide.md)
- [Scraper Monitoring Guide](../scraper-monitoring-guide.md)

---

**Labels**: `enhancement`, `architecture`, `ai-ml`, `rfc`

**Assignees**: TBD

**Milestone**: AI Pipeline Evolution
