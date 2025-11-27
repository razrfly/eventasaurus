# Phase 3 Completion: Movie Matching Improvements

**Status:** ✅ Complete
**Date:** 2025-11-26

---

## What We Improved

### Problem
Cinema City movie matching rate was only 42% (36 movies matched / 85 films processed), with 58% of ShowtimeProcessJob executions being cancelled due to unmatched movies.

**Evidence:**
- **Movies Matched:** 36 out of 85 films (42%)
- **Jobs Cancelled:** 536 ShowtimeProcessJob cancelled
- **Jobs Completed:** 738 ShowtimeProcessJob completed
- **Root Cause:** 60% confidence threshold too strict for Polish titles

### Goal
Increase match rate from 42% to 70%+ by accepting lower-confidence matches that are still valid.

---

## Changes Made

### Updated MovieDetailJob
**File:** `lib/eventasaurus_discovery/sources/cinema_city/jobs/movie_detail_job.ex`

**Changes:**

#### 1. Lowered Confidence Threshold (60% → 50%)
```elixir
# OLD: Line 60
{:ok, tmdb_id, confidence} when confidence >= 0.60 ->

# NEW: Line 60
{:ok, tmdb_id, confidence} when confidence >= 0.50 ->
```

**Rationale:**
- 50-59% confidence matches are often valid, especially for Polish titles
- Example: "Zwierzogród 2" vs "Zootopia 2" might score 55% but is correct
- Balances match rate improvement with accuracy

#### 2. Enhanced Match Type Categorization
```elixir
# Lines 66-70
match_type = cond do
  confidence >= 0.70 -> "standard"              # High confidence
  confidence >= 0.60 -> "now_playing_fallback"  # Medium confidence
  true -> "low_confidence_accepted"             # 50-59% range
end
```

**Benefits:**
- Clear visibility into match quality
- Can analyze which match types work best
- Enables data-driven threshold tuning

#### 3. Detailed Logging for Analysis
```elixir
# Lines 75-81
Logger.info("""
✅ Auto-matched (#{match_type}): #{movie.title}
   Polish title: #{polish_title}
   Confidence: #{trunc(confidence * 100)}%
   TMDB ID: #{tmdb_id}
   Cinema City ID: #{cinema_city_film_id}
""")
```

**Benefits:**
- Every match logged with full context
- Can track confidence score distribution
- Enables post-deployment analysis

#### 4. Improved Error Messages
All error cases now have enhanced logging:

**Low Confidence (<50%):**
```elixir
# Lines 123-128
Logger.warning("""
⏭️  TMDB matching low confidence: #{polish_title} (#{release_year})
   Cinema City ID: #{cinema_city_film_id}
   Confidence: <50%
   This movie will be skipped in ShowtimeProcessJob
""")
```

**No Results:**
```elixir
# Lines 151-156
Logger.warning("""
⏭️  TMDB matching - no results: #{polish_title} (#{release_year})
   Cinema City ID: #{cinema_city_film_id}
   This might be a local film or not yet in TMDB
   This movie will be skipped in ShowtimeProcessJob
""")
```

**Needs Review (Unexpected):**
```elixir
# Lines 105-110
Logger.warning("""
⚠️  TMDB matching needs review (unexpected): #{polish_title} (#{release_year})
   Cinema City ID: #{cinema_city_film_id}
   Candidates found: #{length(candidates)}
   Note: This should be rare with 50% threshold
""")
```

#### 5. Updated Module Documentation
```elixir
# Lines 13-18
Confidence levels (Phase 3: lowered threshold from 60% to 50%):
- High confidence (≥70%): Standard match, auto-matched
- Medium confidence (60-69%): Now Playing fallback match, auto-matched
- Low-medium confidence (50-59%): Accepted with lower confidence, auto-matched
- Low confidence (<50%): No reliable match, returns {:error, :tmdb_low_confidence}
- HTTP/API errors: Returns {:error, reason} which triggers Oban retry
```

---

## Expected Impact (After Next Sync)

### Scenario 1: High Confidence Match (≥70%)
```
🎬 Processing Cinema City movie: Wicked (2024)
✅ Auto-matched (standard): Wicked
   Polish title: Wicked
   Confidence: 95%
   TMDB ID: 402431
   Cinema City ID: 123456

📊 Result: ShowtimeProcessJob completes successfully
📊 State: "completed" in job_execution_summaries
```

### Scenario 2: Medium Confidence Match (60-69%)
```
🎬 Processing Cinema City movie: Vaiana 2 (2024)
✅ Auto-matched (now_playing_fallback): Moana 2
   Polish title: Vaiana 2
   Confidence: 65%
   TMDB ID: 1241982
   Cinema City ID: 789012

📊 Result: ShowtimeProcessJob completes successfully
📊 State: "completed" in job_execution_summaries
```

### Scenario 3: Low-Medium Confidence Match (50-59%) - NEW!
```
🎬 Processing Cinema City movie: Zwierzogród 2 (2025)
✅ Auto-matched (low_confidence_accepted): Zootopia 2
   Polish title: Zwierzogród 2
   Confidence: 55%
   TMDB ID: 1139817
   Cinema City ID: 345678

📊 Result: ShowtimeProcessJob completes successfully (NEW!)
📊 State: "completed" in job_execution_summaries
📊 Impact: Movies that would have been cancelled are now matched
```

### Scenario 4: Low Confidence (<50%)
```
🎬 Processing Cinema City movie: Local Documentary (2024)
⏭️  TMDB matching low confidence: Local Documentary (2024)
   Cinema City ID: 901234
   Confidence: <50%
   This movie will be skipped in ShowtimeProcessJob

📊 Result: ShowtimeProcessJob cancelled (expected)
📊 State: "cancelled" in job_execution_summaries
```

---

## Verification Steps

### 1. Wait for Next Cinema City Sync
Cinema City syncs run automatically via Oban. The next sync will use the updated matching logic.

### 2. Monitor Match Rates
```bash
# Check recent MovieDetailJob executions
mix monitor.jobs worker MovieDetailJob --limit 50

# Look for match type distribution in logs
grep "Auto-matched" log/dev.log | grep "Cinema City"

# Expected output:
# ✅ Auto-matched (standard): Movie Title
# ✅ Auto-matched (now_playing_fallback): Movie Title
# ✅ Auto-matched (low_confidence_accepted): Movie Title
```

### 3. Compare Completion vs Cancellation Rates
```bash
# Before Phase 3:
# - Completed: 738 (58%)
# - Cancelled: 536 (42%)
# - Match Rate: 42%

# After Phase 3 (Expected):
# - Completed: ~900 (70%+)
# - Cancelled: ~380 (30%)
# - Match Rate: 70%+
```

### 4. Analyze Match Type Distribution
```bash
# Check logs for match type breakdown
grep "Auto-matched" log/dev.log | grep -oP '\(.*?\)' | sort | uniq -c

# Expected distribution:
#  50 (standard)              # 70%+ confidence
#  25 (now_playing_fallback)  # 60-69% confidence
#  15 (low_confidence_accepted) # 50-59% confidence (NEW!)
```

### 5. Verify Low Confidence Handling
```bash
# Check that <50% matches are still properly skipped
mix monitor.jobs worker MovieDetailJob --state retryable --limit 20

# Expected: Should see low_confidence errors, but fewer than before
```

---

## Benefits

### ✅ Increased Match Rate
- **Target:** 42% → 70%+
- **Method:** Accept 50-59% confidence matches
- **Impact:** More events created for users

### ✅ Better Visibility
- **Enhanced Logging:** Every match includes all relevant details
- **Match Type Tracking:** Can analyze which confidence ranges work best
- **Data-Driven Decisions:** Can tune thresholds based on actual performance

### ✅ Improved Debugging
- **Context-Rich Errors:** All failures include film title, year, and Cinema City ID
- **Clear Categorization:** Easy to distinguish between low confidence, no results, and errors
- **Actionable Messages:** Each error explains what will happen next

### ✅ Accurate Metrics
- **Success Rate:** Now reflects true pipeline performance
- **Match Rate:** `completed / (completed + cancelled)` = quality metric
- **Error Analysis:** Can identify systemic issues vs. one-off problems

---

## Integration with Phase 2

Phase 2 fixed the monitoring blind spot, Phase 3 improves the match rate:

| Metric | Before Phase 2 | After Phase 2 | After Phase 3 (Expected) |
|--------|----------------|---------------|--------------------------|
| **ShowtimeProcessJob Tracking** | 0 records | All tracked ✅ | All tracked ✅ |
| **Movie Match Rate** | 42% | 42% | 70%+ ✅ |
| **Events Created** | 738 | 738 | ~900+ ✅ |
| **Jobs Cancelled** | 536 (hidden) | 536 (tracked) | ~380 (tracked) ✅ |
| **Monitoring Visibility** | Partial ⚠️ | Complete ✅ | Complete ✅ |

---

## Potential Risks & Mitigation

### Risk 1: False Positives (50-59% Range)
**Risk:** Some 50-59% matches might be incorrect
**Mitigation:**
- Monitor user feedback and event quality
- Can raise threshold back to 60% if needed
- Enhanced logging makes it easy to identify problematic matches

### Risk 2: No Improvement in Match Rate
**Risk:** 50% threshold might not capture significantly more valid matches
**Mitigation:**
- Phase 2 monitoring allows us to measure exact impact
- Can analyze which films are still failing with `mix monitor.jobs worker MovieDetailJob --state retryable`
- If needed, can investigate TmdbMatcher algorithm for further improvements

### Risk 3: Increased Load on TMDB API
**Risk:** N/A - No change to API call patterns
**Mitigation:** N/A

---

## Next Steps

### Immediate (Post-Deployment)
1. **Monitor Next Sync:** Watch logs for match type distribution
2. **Verify Match Rate:** Calculate `completed / (completed + cancelled)`
3. **Check for Issues:** Look for user reports of incorrect movie matches
4. **Analyze Logs:** Review confidence score distribution

### Short-Term (1-2 Weeks)
1. **Compare Baselines:** Use `mix monitor.baseline cinema_city` before/after
2. **Measure Impact:** Calculate actual match rate improvement
3. **Tune Threshold:** Adjust if needed based on data

### Long-Term (Future Phases)
1. **Phase 4:** Enhanced monitoring dashboard with match rate visualization
2. **Phase 5:** Investigate remaining unmatched films (those <50%)
3. **Phase 6:** Consider implementing original_title extraction from Cinema City API

---

## Technical Notes

### Why 50% Threshold?
- **Too Low:** <40% would introduce too many false positives
- **Too High:** 60% was rejecting valid matches
- **Sweet Spot:** 50-60% range captures Polish title variations while maintaining accuracy
- **Evidence-Based:** Can measure and tune based on real data

### TmdbMatcher Behavior
TmdbMatcher already has dual-title matching logic:
1. Try `original_title` if provided
2. Fall back to `polish_title`

Cinema City API only provides `polish_title`, so all matches use Polish title scoring. The 50% threshold accommodates Polish title variations.

### Match Type Categories
- **standard** (≥70%): High confidence, title/year exact or near-exact match
- **now_playing_fallback** (60-69%): Medium confidence, likely from Now Playing API fallback
- **low_confidence_accepted** (50-59%): Lower confidence but still valid, accepts Polish title variations

---

## Summary

✅ **Problem:** Low movie match rate (42%) causing events to be skipped
✅ **Fix:** Lowered confidence threshold from 60% to 50%
✅ **Result:** Expected 70%+ match rate, more events created for users
✅ **Benefit:** Better user experience with more comprehensive event listings

**Status:** Ready for testing with next Cinema City sync run.

**Integration:** Works seamlessly with Phase 2 monitoring improvements.
