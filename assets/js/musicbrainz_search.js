import { MusicBrainzApi } from 'musicbrainz-api';

/**
 * MusicBrainz Search Module for Eventasaurus
 * 
 * Provides better search relevance and built-in rate limiting
 * compared to direct API calls. Focuses on tracks/recordings only.
 */

export const MusicBrainzSearch = {
  api: null,
  rateLimiter: null,
  
  // Initialize the API client
  init() {
    if (!this.api) {
      this.api = new MusicBrainzApi({
        appName: 'Eventasaurus',
        appVersion: '1.0.0',
        appContactInfo: 'https://eventasaurus.com'
      });
      
      // Initialize rate limiter (MusicBrainz enforces 1 req/sec)
      this.rateLimiter = {
        lastRequest: 0,
        minInterval: 1000, // 1 second
        queue: [],
        processing: false
      };
    }
  },

  // Rate-limited request wrapper
  async makeRequest(requestFn) {
    this.init();
    
    return new Promise((resolve, reject) => {
      this.rateLimiter.queue.push({ requestFn, resolve, reject });
      this.processQueue();
    });
  },

  // Process queued requests with rate limiting
  async processQueue() {
    if (this.rateLimiter.processing || this.rateLimiter.queue.length === 0) {
      return;
    }

    this.rateLimiter.processing = true;

    while (this.rateLimiter.queue.length > 0) {
      const now = Date.now();
      const timeSinceLastRequest = now - this.rateLimiter.lastRequest;
      
      if (timeSinceLastRequest < this.rateLimiter.minInterval) {
        const delay = this.rateLimiter.minInterval - timeSinceLastRequest;
        await this.sleep(delay);
      }

      const { requestFn, resolve, reject } = this.rateLimiter.queue.shift();
      
      try {
        this.rateLimiter.lastRequest = Date.now();
        const result = await requestFn();
        resolve(result);
      } catch (error) {
        reject(error);
      }
    }

    this.rateLimiter.processing = false;
  },

  // Helper to sleep for rate limiting
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  },

  // Search for music tracks with improved relevance
  async searchTracks(query, limit = 8) {
    if (!query || query.trim().length < 2) {
      return { results: [] };
    }

    try {
      const searchResults = await this.makeRequest(async () => {
        // Get more results for better deduplication (limit * 3, max 25)
        const searchLimit = Math.min(limit * 3, 25);
        return await this.api.search('recording', {
          query: this.buildSearchQuery(query),
          limit: searchLimit,
          offset: 0
        });
      });

      if (!searchResults || !searchResults.recordings) {
        return { results: [] };
      }

      // Process and normalize results
      const processedResults = searchResults.recordings
        .map(recording => this.normalizeRecording(recording))
        .filter(result => result !== null)
        .sort((a, b) => this.calculateRelevanceScore(b, query) - this.calculateRelevanceScore(a, query));

      // Deduplicate by title and main artist
      const dedupedResults = this.deduplicateResults(processedResults);
      
      // Return top results
      const finalResults = dedupedResults.slice(0, limit);
      
      console.log(`MusicBrainz search: "${query}" returned ${searchResults.recordings.length} raw, ${finalResults.length} final results`);
      
      return { results: finalResults };
      
    } catch (error) {
      console.error('MusicBrainz search error:', error);
      
      // Handle rate limiting gracefully
      if (error.message?.includes('rate limit') || error.message?.includes('503')) {
        return { 
          error: 'Rate limit exceeded, please try again later',
          results: [] 
        };
      }
      
      return { 
        error: 'Search failed, please try again',
        results: [] 
      };
    }
  },

  // Get detailed information for a specific recording
  async getRecordingDetails(mbid) {
    if (!mbid) {
      throw new Error('MusicBrainz ID is required');
    }

    try {
      const details = await this.makeRequest(async () => {
        return await this.api.lookup('recording', mbid, {
          inc: ['releases', 'artist-credits', 'isrcs']
        });
      });

      return this.normalizeRecording(details, true);
      
    } catch (error) {
      console.error('MusicBrainz details error:', error);
      throw new Error(`Failed to get recording details: ${error.message}`);
    }
  },

  // Build optimized search query
  buildSearchQuery(query) {
    // Clean up the query and add some search improvements
    const cleanQuery = query.trim().replace(/[^\w\s'"]/g, '').replace(/\s+/g, ' ');
    
    // For short queries, search more broadly
    if (cleanQuery.split(' ').length <= 2) {
      return `recording:"${cleanQuery}"~2 OR recording:${cleanQuery}`;
    }
    
    return cleanQuery;
  },

  // Normalize a recording result to our standard format
  normalizeRecording(recording, includeExtraDetails = false) {
    try {
      const primaryArtist = this.extractPrimaryArtist(recording['artist-credit'] || recording.artistCredit);
      const releases = recording.releases || [];
      const bestRelease = this.findBestRelease(releases);
      
      const normalized = {
        id: recording.id,
        type: 'track',
        title: recording.title,
        description: this.buildDescription(primaryArtist, bestRelease),
        image_url: null,
        images: [],
        metadata: {
          musicbrainz_id: recording.id,
          length: recording.length,
          disambiguation: recording.disambiguation,
          artist_credit: recording['artist-credit'] || recording.artistCredit || [],
          releases: releases.slice(0, 3), // Limit releases for performance
          score: recording.score || 0,
          media_type: 'recording',
          duration_ms: recording.length,
          duration_formatted: this.formatDuration(recording.length)
        }
      };

      if (includeExtraDetails) {
        normalized.metadata.isrcs = recording.isrcs || [];
        normalized.additional_data = {
          releases: releases,
          isrcs: recording.isrcs || []
        };
      }

      return normalized;
      
    } catch (error) {
      console.error('Error normalizing recording:', error);
      return null;
    }
  },

  // Extract primary artist name from artist credit
  extractPrimaryArtist(artistCredit) {
    if (!artistCredit || !Array.isArray(artistCredit) || artistCredit.length === 0) {
      return 'Unknown Artist';
    }
    
    const firstCredit = artistCredit[0];
    if (firstCredit && firstCredit.artist) {
      return firstCredit.artist.name || firstCredit.name || 'Unknown Artist';
    }
    
    return firstCredit?.name || 'Unknown Artist';
  },

  // Find the best release from available releases
  findBestRelease(releases) {
    if (!releases || releases.length === 0) {
      return null;
    }
    
    // Prefer official releases, then earliest date
    const official = releases.filter(r => r.status === 'Official');
    const toSort = official.length > 0 ? official : releases;
    
    return toSort.sort((a, b) => {
      // Sort by date (earliest first)
      const dateA = a.date || '9999';
      const dateB = b.date || '9999';
      return dateA.localeCompare(dateB);
    })[0];
  },

  // Build description string
  buildDescription(artist, release) {
    if (release && release.title) {
      return `${artist} - ${release.title}`;
    }
    return artist;
  },

  // Format duration from milliseconds to MM:SS
  formatDuration(milliseconds) {
    if (!milliseconds || isNaN(milliseconds)) return null;
    
    const seconds = Math.floor(milliseconds / 1000);
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  },

  // Calculate relevance score for sorting
  calculateRelevanceScore(result, originalQuery) {
    let score = result.metadata.score || 0;
    
    // Boost score based on number of releases (popularity indicator)
    const releaseCount = (result.metadata.releases || []).length;
    score += Math.min(releaseCount, 5); // Cap at 5 bonus points
    
    // Boost score for exact title matches
    const queryWords = originalQuery.toLowerCase().split(' ');
    const titleWords = result.title.toLowerCase().split(' ');
    
    for (const queryWord of queryWords) {
      if (titleWords.some(titleWord => titleWord.includes(queryWord))) {
        score += 10;
      }
    }
    
    return score;
  },

  // Deduplicate results by title and artist
  deduplicateResults(results) {
    const seen = new Map();
    const deduped = [];
    
    for (const result of results) {
      const artist = this.extractPrimaryArtist(result.metadata.artist_credit);
      const title = result.title.toLowerCase().trim();
      const key = `${title}::${artist.toLowerCase().trim()}`;
      
      if (!seen.has(key)) {
        seen.set(key, result);
        deduped.push(result);
      } else {
        // Keep the one with higher score
        const existing = seen.get(key);
        const existingScore = this.calculateRelevanceScore(existing, title);
        const currentScore = this.calculateRelevanceScore(result, title);
        
        if (currentScore > existingScore) {
          // Replace in both map and array
          seen.set(key, result);
          const index = deduped.indexOf(existing);
          if (index !== -1) {
            deduped[index] = result;
          }
        }
      }
    }
    
    return deduped;
  }
};

// Export for use with Phoenix LiveView hooks
window.MusicBrainzSearch = MusicBrainzSearch;