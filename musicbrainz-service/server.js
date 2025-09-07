const express = require('express');
const cors = require('cors');
const MusicBrainzApi = require('musicbrainz-api').MusicBrainzApi;

const app = express();
const port = 3001;

// Initialize MusicBrainz API with proper user agent
const mbApi = new MusicBrainzApi({
  appName: 'Eventasaurus',
  appVersion: '1.0.0',
  appContactInfo: 'https://eventasaurus.com'
});

app.use(cors());
app.use(express.json());

// Enhanced search with better relevance and deduplication
app.post('/search', async (req, res) => {
  try {
    const { query, type = 'recording', limit = 8 } = req.body;
    
    if (!query || query.trim().length === 0) {
      return res.json({ results: [] });
    }

    console.log(`Searching for: "${query}" (type: ${type})`);
    
    // Use advanced search with better query construction
    const searchResults = await mbApi.search(type, {
      query: query,
      limit: Math.min(limit * 3, 25), // Get more results for better deduplication
      offset: 0
    });

    if (!searchResults || !searchResults[type + 's']) {
      return res.json({ results: [] });
    }

    // Process and deduplicate results
    const results = searchResults[type + 's']
      .map(item => normalizeResult(item, type))
      .filter(item => item !== null)
      .sort((a, b) => {
        // Sort by relevance score and popularity
        const scoreA = (a.score || 0) + (getPopularityBonus(a) * 10);
        const scoreB = (b.score || 0) + (getPopularityBonus(b) * 10);
        return scoreB - scoreA;
      });

    // Deduplicate by title and main artist
    const deduped = deduplicateResults(results);
    
    // Return top results
    const finalResults = deduped.slice(0, limit);
    
    console.log(`Found ${searchResults[type + 's'].length} raw results, returning ${finalResults.length} after processing`);
    
    res.json({ results: finalResults });
    
  } catch (error) {
    console.error('Search error:', error.message);
    
    // Handle rate limiting gracefully
    if (error.message.includes('rate limit') || error.message.includes('503')) {
      return res.status(429).json({ 
        error: 'Rate limit exceeded, please try again later',
        results: [] 
      });
    }
    
    res.status(500).json({ 
      error: 'Search failed', 
      details: error.message,
      results: [] 
    });
  }
});

// Get detailed information for a specific recording
app.post('/details', async (req, res) => {
  try {
    const { id, type = 'recording' } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'ID is required' });
    }

    const details = await mbApi.lookup(type, id, ['releases', 'artist-credits', 'isrcs']);
    const normalized = normalizeDetailedResult(details, type);
    
    res.json({ result: normalized });
    
  } catch (error) {
    console.error('Details error:', error.message);
    res.status(500).json({ 
      error: 'Failed to get details', 
      details: error.message 
    });
  }
});

function normalizeResult(item, type) {
  try {
    if (type === 'recording') {
      const primaryArtist = extractPrimaryArtist(item['artist-credit']);
      const releases = item.releases || [];
      const bestRelease = findBestRelease(releases);
      
      return {
        id: item.id,
        type: 'track',
        title: item.title,
        description: buildDescription(primaryArtist, bestRelease),
        image_url: null,
        images: [],
        metadata: {
          musicbrainz_id: item.id,
          length: item.length,
          disambiguation: item.disambiguation,
          artist_credit: item['artist-credit'] || [],
          releases: releases.slice(0, 3), // Limit releases for performance
          score: item.score || 0,
          media_type: 'recording',
          duration_ms: item.length,
          duration_formatted: formatDuration(item.length)
        }
      };
    }
    
    // Handle other types (artist, release-group) if needed
    return null;
    
  } catch (error) {
    console.error('Error normalizing result:', error);
    return null;
  }
}

function normalizeDetailedResult(item, type) {
  // Similar to normalizeResult but with more detailed information
  return normalizeResult(item, type);
}

function extractPrimaryArtist(artistCredit) {
  if (!artistCredit || !Array.isArray(artistCredit)) {
    return 'Unknown Artist';
  }
  
  const firstCredit = artistCredit[0];
  if (firstCredit && firstCredit.artist) {
    return firstCredit.artist.name || firstCredit.name || 'Unknown Artist';
  }
  
  return 'Unknown Artist';
}

function findBestRelease(releases) {
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
}

function buildDescription(artist, release) {
  if (release && release.title) {
    return `${artist} - ${release.title}`;
  }
  return artist;
}

function formatDuration(milliseconds) {
  if (!milliseconds) return null;
  
  const seconds = Math.floor(milliseconds / 1000);
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  
  return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
}

function getPopularityBonus(result) {
  // Give bonus points for having more releases (indicator of popularity)
  const releaseCount = (result.metadata.releases || []).length;
  return Math.min(releaseCount, 5); // Cap at 5 bonus points
}

function deduplicateResults(results) {
  const seen = new Map();
  const deduped = [];
  
  for (const result of results) {
    const artist = extractPrimaryArtist(result.metadata.artist_credit);
    const title = result.title.toLowerCase().trim();
    const key = `${title}::${artist.toLowerCase().trim()}`;
    
    if (!seen.has(key)) {
      seen.set(key, result);
      deduped.push(result);
    } else {
      // Keep the one with higher score
      const existing = seen.get(key);
      if ((result.metadata.score || 0) > (existing.metadata.score || 0)) {
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

app.listen(port, () => {
  console.log(`MusicBrainz service running on port ${port}`);
});