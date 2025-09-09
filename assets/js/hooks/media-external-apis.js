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

    // Initialize MusicBrainz search
    if (window.MusicBrainzSearch) {
      window.MusicBrainzSearch.init();
    }

    // Set up debounced search
    this.inputEl.addEventListener('input', (e) => {
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
    });

    // Hide results when clicking outside
    document.addEventListener('click', (e) => {
      if (!this.el.contains(e.target) && !this.resultsContainer?.contains(e.target)) {
        this.hideResults();
      }
    });
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

    if (results.length === 0) {
      this.resultsList.innerHTML = '<div class="p-4 text-gray-500 text-center">No tracks found</div>';
    } else {
      this.resultsList.innerHTML = results.map(result => this.createResultHTML(result)).join('');
      
      // Add click handlers to result buttons
      this.resultsList.querySelectorAll('.music-result-button').forEach(button => {
        button.addEventListener('click', (e) => {
          const trackData = JSON.parse(button.dataset.track);
          this.selectTrack(trackData);
        });
      });
    }

    this.showResults();
  },

  createResultHTML(result) {
    const artist = this.extractArtistNames(result.metadata.artist_credit);
    const duration = result.metadata.duration_formatted || '';
    
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
            ${duration ? `<p class="text-xs text-gray-500">Duration: ${duration}</p>` : ''}
          </div>
          <button
            type="button"
            class="music-result-button ml-3 px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
            data-track='${JSON.stringify(result)}'
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
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout);
    }
  }
};

// Export all media hooks as a default object for easy importing
export default {
  MusicTrackSearch
};