// Media and external API hooks for music search integration
// Extracted from app.js for better organization

// MusicTrackSearch hook for music track search integration
export const MusicTrackSearch = {
  mounted() {
    this.inputEl = this.el;
    this.resultsContainer = document.getElementById('music-search-results');
    this.resultsList = document.getElementById('music-results-list');
    this.loadingIndicator = document.getElementById('music-search-loading');
    this.searchTimeout = null;
    this.currentQuery = '';
    this.resultButtonListeners = new Map(); // Track button listeners for cleanup
    this.trackDataCache = new Map(); // In-memory cache for track data (security fix)

    // Verify required elements exist
    if (!this.inputEl) {
      console.error('MusicTrackSearch: Input element not found');
      return;
    }

    // Initialize MusicBrainz search
    if (window.MusicBrainzSearch) {
      window.MusicBrainzSearch.init();
    }

    // Set up debounced search - bind to maintain context for cleanup
    this.handleInput = (e) => {
      const query = e.target.value.trim();
      
      if (this.searchTimeout) {
        clearTimeout(this.searchTimeout);
      }

      if (query.length < 2) {
        this.hideResults();
        return;
      }

      this.showLoading();
      
      this.searchTimeout = setTimeout(async () => {
        await this.performSearch(query);
      }, 300);
    };

    this.inputEl.addEventListener('input', this.handleInput);

    // Hide results when clicking outside - bind to maintain context for cleanup
    this.handleDocumentClick = (e) => {
      if (!this.el.contains(e.target) && !this.resultsContainer?.contains(e.target)) {
        this.hideResults();
      }
    };

    document.addEventListener('click', this.handleDocumentClick);
  },

  async performSearch(query) {
    if (!window.MusicBrainzSearch) {
      console.error('MusicBrainzSearch not available');
      this.hideLoading();
      return;
    }

    this.currentQuery = query;

    try {
      const response = await window.MusicBrainzSearch.searchTracks(query, 8);
      
      // Only update results if this is still the current query
      if (query === this.currentQuery) {
        this.hideLoading();
        this.displayResults(response.results);
      }
    } catch (error) {
      console.error('Music search error:', error);
      this.hideLoading();
      this.showError('Search failed. Please try again.');
    }
  },

  displayResults(results) {
    if (!this.resultsList || !this.resultsContainer) return;

    // Clean up previous button listeners and cached data
    this.cleanupButtonListeners();
    this.trackDataCache.clear();

    if (results.length === 0) {
      this.resultsList.innerHTML = '<div class="p-4 text-gray-500 text-center">No tracks found</div>';
    } else {
      this.resultsList.innerHTML = results.map((result, index) => this.createResultHTML(result, index)).join('');
      
      // Add click handlers to result buttons and track them for cleanup
      this.resultsList.querySelectorAll('.music-result-button').forEach(button => {
        const handler = (e) => {
          const trackId = button.dataset.trackId;
          const trackData = this.trackDataCache.get(trackId);
          if (trackData) {
            this.selectTrack(trackData);
          } else {
            console.error('Track data not found for ID:', trackId);
          }
        };
        
        button.addEventListener('click', handler);
        this.resultButtonListeners.set(button, handler);
      });
    }

    this.showResults();
  },

  cleanupButtonListeners() {
    // Remove all tracked button listeners
    this.resultButtonListeners.forEach((handler, button) => {
      button.removeEventListener('click', handler);
    });
    this.resultButtonListeners.clear();
  },

  createResultHTML(result, index) {
    const artist = this.extractArtistNames(result.metadata.artist_credit);
    const duration = result.metadata.duration_formatted || '';
    
    // Generate safe track ID and store in memory cache
    const trackId = `track_${Date.now()}_${index}`;
    this.trackDataCache.set(trackId, result);
    
    return `
      <div class="border rounded-lg p-3 bg-white hover:bg-gray-50">
        <div class="flex justify-between items-start">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <svg class="h-4 w-4 text-blue-600 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                <path d="M18 3a1 1 0 00-1.196-.98l-10 2A1 1 0 006 5v6.114A4.978 4.978 0 003 11c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V5.82l8-1.6v5.894A4.978 4.978 0 0011 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V3z"/>
              </svg>
              <h5 class="font-medium text-gray-900 truncate">${this.escapeHtml(result.title)}</h5>
            </div>
            <p class="text-sm text-gray-600 mb-1">${this.escapeHtml(artist)}</p>
            ${duration ? `<p class="text-xs text-gray-500">Duration: ${this.escapeHtml(duration)}</p>` : ''}
          </div>
          <button
            type="button"
            class="music-result-button ml-3 px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
            data-track-id="${this.escapeHtml(trackId)}"
          >
            Add Track
          </button>
        </div>
      </div>
    `;
  },

  selectTrack(trackData) {
    // Send event to Phoenix LiveView component
    this.pushEvent("music_track_selected", { track: trackData });
    
    // Clear search
    this.inputEl.value = '';
    this.hideResults();
  },

  extractArtistNames(artistCredit) {
    if (!Array.isArray(artistCredit) || artistCredit.length === 0) {
      return 'Unknown Artist';
    }
    
    return artistCredit
      .map(credit => credit.name || credit.artist?.name)
      .filter(name => name)
      .join(', ') || 'Unknown Artist';
  },

  showResults() {
    if (this.resultsContainer) {
      this.resultsContainer.style.display = 'block';
    }
  },

  hideResults() {
    if (this.resultsContainer) {
      this.resultsContainer.style.display = 'none';
    }
  },

  showLoading() {
    if (this.loadingIndicator) {
      this.loadingIndicator.classList.remove('hidden');
    }
  },

  hideLoading() {
    if (this.loadingIndicator) {
      this.loadingIndicator.classList.add('hidden');
    }
  },

  showError(message) {
    if (this.resultsList) {
      this.resultsList.innerHTML = `<div class="p-4 text-red-500 text-center">${message}</div>`;
      this.showResults();
    }
  },

  escapeHtml(unsafe) {
    return unsafe
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  },

  destroyed() {
    // Clear any pending search timeout
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout);
    }

    // Clean up button listeners and cached data
    this.cleanupButtonListeners();
    this.trackDataCache.clear();

    // Remove main event listeners
    if (this.inputEl && this.handleInput) {
      this.inputEl.removeEventListener('input', this.handleInput);
    }

    if (this.handleDocumentClick) {
      document.removeEventListener('click', this.handleDocumentClick);
    }
  }
};

// Export all media hooks as a default object for easy importing
export default {
  MusicTrackSearch
};