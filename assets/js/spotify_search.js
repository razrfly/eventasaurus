/**
 * Spotify Search Module for Eventasaurus
 * 
 * Provides client-side access token management and search functionality
 * using the Spotify Web API. Works in conjunction with the server-side
 * SpotifyService for consistent data handling.
 */

export const SpotifySearch = {
  accessToken: null,
  tokenExpiry: null,
  rateLimiter: null,
  isInitialized: false,
  
  // Initialize the search module
  async init() {
    if (this.isInitialized) return;
    
    // Get access token from server
    await this.refreshAccessToken();
    
    // Initialize rate limiter (Spotify allows 100 req/second)
    this.rateLimiter = {
      lastRequest: 0,
      minInterval: 10, // 100ms between requests (10 req/sec to be safe)
      queue: [],
      processing: false
    };
    
    this.isInitialized = true;
  },

  // Get a fresh access token from our server
  async refreshAccessToken() {
    try {
      const response = await fetch('/api/spotify/token', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`Token request failed: ${response.status}`);
      }

      const data = await response.json();
      this.accessToken = data.access_token;
      this.tokenExpiry = Date.now() + (data.expires_in * 1000) - 60000; // 1 minute buffer
      
      console.log('Spotify access token refreshed');
    } catch (error) {
      console.error('Failed to get Spotify access token:', error);
      throw error;
    }
  },

  // Ensure we have a valid access token
  async ensureValidToken() {
    if (!this.accessToken || Date.now() >= this.tokenExpiry) {
      await this.refreshAccessToken();
    }
  },

  // Rate-limited request wrapper
  async makeRequest(requestFn) {
    await this.init();
    
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

  // Search for tracks with improved relevance
  async searchTracks(query, limit = 20) {
    if (!query || query.trim().length < 2) {
      return { results: [] };
    }

    try {
      const searchResults = await this.makeRequest(async () => {
        await this.ensureValidToken();
        
        const url = new URL('https://api.spotify.com/v1/search');
        url.searchParams.append('q', query.trim());
        url.searchParams.append('type', 'track');
        url.searchParams.append('limit', Math.min(limit, 50)); // Spotify max is 50
        url.searchParams.append('offset', 0);

        const response = await fetch(url, {
          headers: {
            'Authorization': `Bearer ${this.accessToken}`,
            'Content-Type': 'application/json',
          },
        });

        if (response.status === 401) {
          // Token expired, refresh and retry
          await this.refreshAccessToken();
          return fetch(url, {
            headers: {
              'Authorization': `Bearer ${this.accessToken}`,
              'Content-Type': 'application/json',
            },
          });
        }

        return response;
      });

      if (!searchResults.ok) {
        throw new Error(`Spotify search failed: ${searchResults.status}`);
      }

      const data = await searchResults.json();
      
      if (!data.tracks || !data.tracks.items) {
        return { results: [] };
      }

      // Process and normalize results
      const processedResults = data.tracks.items
        .map(track => this.normalizeTrack(track))
        .filter(result => result !== null)
        .sort((a, b) => this.calculateRelevanceScore(b, query) - this.calculateRelevanceScore(a, query));

      // Deduplicate by title and main artist
      const dedupedResults = this.deduplicateResults(processedResults);
      
      // Return requested number of results
      const finalResults = dedupedResults.slice(0, limit);
      
      console.log(`Spotify search: "${query}" returned ${data.tracks.items.length} raw, ${finalResults.length} final results`);
      
      return { results: finalResults };
      
    } catch (error) {
      console.error('Spotify search error:', error);
      
      // Handle rate limiting gracefully
      if (error.message?.includes('rate limit') || error.message?.includes('429')) {
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

  // Get detailed information for a specific track
  async getTrackDetails(trackId) {
    if (!trackId) {
      throw new Error('Track ID is required');
    }

    try {
      const response = await this.makeRequest(async () => {
        await this.ensureValidToken();
        
        // Get basic track info and audio features in parallel
        const trackUrl = `https://api.spotify.com/v1/tracks/${trackId}`;
        const featuresUrl = `https://api.spotify.com/v1/audio-features/${trackId}`;

        const headers = {
          'Authorization': `Bearer ${this.accessToken}`,
          'Content-Type': 'application/json',
        };

        const [trackResponse, featuresResponse] = await Promise.all([
          fetch(trackUrl, { headers }),
          fetch(featuresUrl, { headers })
        ]);

        if (!trackResponse.ok) {
          throw new Error(`Track request failed: ${trackResponse.status}`);
        }

        const trackData = await trackResponse.json();
        let featuresData = {};

        // Audio features request might fail for some tracks
        if (featuresResponse.ok) {
          featuresData = await featuresResponse.json();
        }

        return { track: trackData, features: featuresData };
      });

      return this.normalizeTrackWithFeatures(response.track, response.features);
      
    } catch (error) {
      console.error('Spotify track details error:', error);
      throw new Error(`Failed to get track details: ${error.message}`);
    }
  },

  // Normalize a track result to our standard format
  normalizeTrack(track) {
    try {
      const artists = track.artists || [];
      const artistNames = artists.map(artist => artist.name);
      const primaryArtist = artistNames[0] || "Unknown Artist";
      
      const album = track.album || {};
      const images = album.images || [];
      
      // Get the medium-sized image (usually 300x300)
      const image_url = this.getBestImageUrl(images);

      return {
        id: track.id,
        type: 'track',
        title: track.name,
        description: this.buildDescription(primaryArtist, album.name),
        image_url: image_url,
        images: this.normalizeImages(images),
        metadata: {
          spotify_id: track.id,
          artist: primaryArtist,
          artists: artistNames,
          album: album.name,
          album_release_date: album.release_date,
          album_type: album.album_type,
          duration_ms: track.duration_ms,
          duration_formatted: this.formatDuration(track.duration_ms),
          popularity: track.popularity,
          explicit: track.explicit,
          preview_url: track.preview_url,
          disc_number: track.disc_number,
          track_number: track.track_number,
          external_url: track.external_urls?.spotify
        }
      };
      
    } catch (error) {
      console.error('Error normalizing track:', error);
      return null;
    }
  },

  // Normalize track with audio features
  normalizeTrackWithFeatures(track, features) {
    const basic = this.normalizeTrack(track);
    
    if (!basic) return null;

    // Add audio features if available
    if (features && typeof features === 'object' && features.id) {
      basic.metadata.audio_features = {
        danceability: features.danceability,
        energy: features.energy,
        key: features.key,
        loudness: features.loudness,
        mode: features.mode,
        speechiness: features.speechiness,
        acousticness: features.acousticness,
        instrumentalness: features.instrumentalness,
        liveness: features.liveness,
        valence: features.valence,
        tempo: features.tempo,
        time_signature: features.time_signature
      };
    }

    return basic;
  },

  // Normalize images array
  normalizeImages(images) {
    if (!Array.isArray(images)) return [];
    
    return images.map(image => ({
      url: image.url,
      width: image.width,
      height: image.height,
      type: 'cover',
      size: `${image.width}x${image.height}`
    }));
  },

  // Get the best image URL from available images
  getBestImageUrl(images) {
    if (!Array.isArray(images) || images.length === 0) return null;
    
    // Try to get medium size (around 300px)
    const mediumImage = images.find(img => img.width >= 250 && img.width <= 400);
    if (mediumImage) return mediumImage.url;
    
    // Fallback to first available
    return images[0]?.url || null;
  },

  // Build description string
  buildDescription(artist, album) {
    if (album && album.trim()) {
      return `${artist} - ${album}`;
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
    let score = result.metadata.popularity || 0;
    
    // Boost score for exact title matches
    const queryWords = originalQuery.toLowerCase().split(' ');
    const titleWords = result.title.toLowerCase().split(' ');
    
    for (const queryWord of queryWords) {
      if (titleWords.some(titleWord => titleWord.includes(queryWord))) {
        score += 20; // Higher boost than MusicBrainz since we have popularity scores
      }
    }
    
    // Boost for tracks with preview URLs
    if (result.metadata.preview_url) {
      score += 5;
    }
    
    return score;
  },

  // Deduplicate results by title and artist
  deduplicateResults(results) {
    const seen = new Map();
    const deduped = [];
    
    for (const result of results) {
      const title = result.title.toLowerCase().trim();
      const artist = result.metadata.artist.toLowerCase().trim();
      const key = `${title}::${artist}`;
      
      if (!seen.has(key)) {
        seen.set(key, result);
        deduped.push(result);
      } else {
        // Keep the one with higher popularity
        const existing = seen.get(key);
        const existingPopularity = existing.metadata.popularity || 0;
        const currentPopularity = result.metadata.popularity || 0;
        
        if (currentPopularity > existingPopularity) {
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
window.SpotifySearch = SpotifySearch;