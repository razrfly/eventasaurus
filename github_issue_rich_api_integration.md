# Feature Request: Rich API Data Integration for Event Enhancement

## Overview

Expand the current image selection system to support rich data integration from external APIs, starting with The Movie Database (TMDB) and designed to support additional APIs in the future. When users select content from external APIs, they should be able to automatically populate event details with rich metadata from the source.

## Current State

✅ **Existing Integration:**
- Unified image picker supporting Unsplash and TMDB
- Basic metadata storage in `external_image_data` JSON field
- Search functionality across both APIs
- Proper API authentication and error handling

## Proposed Feature

### 1. Enhanced Movie Database Integration

When a user selects a movie from TMDB, provide an option to **"Import Movie Details"** that would:

**Data to Import:**
- ✨ **Basic Info**: Title, overview, release date, runtime, genres
- 🎬 **Cast & Crew**: Director, main actors with profile images
- 🖼️ **Rich Media**: Multiple posters, backdrops, trailers
- 🔗 **Links**: Official TMDB page, homepage, social media
- ⭐ **Ratings**: TMDB rating, vote count
- 🏷️ **Additional**: Production companies, budget, revenue, languages

**Example Data Structure:**
```json
{
  "source": "tmdb",
  "type": "movie",
  "tmdb_id": 1100988,
  "title": "28 Years Later",
  "overview": "It's been almost three decades since the rage virus escaped...",
  "release_date": "2025-06-18",
  "runtime": null,
  "genres": ["Horror", "Science Fiction", "Thriller"],
  "poster_path": "/qYOKfOwMdnWGBnIvEOsf3fS6xMy.jpg",
  "backdrop_path": "/18TSJF1WLA4CkymvVUcKDBwUJ9F.jpg",
  "vote_average": 0.0,
  "vote_count": 0,
  "director": {
    "name": "Danny Boyle",
    "profile_path": "/p1HnCCGZspQ7HgiBf5gKBHVXLqV.jpg"
  },
  "cast": [
    {
      "name": "Aaron Taylor-Johnson",
      "character": "Jim",
      "profile_path": "/gqWaYZEZp1YX8qGN4PBr7JHV9Q4.jpg"
    },
    {
      "name": "Jodie Comer",
      "character": "Unknown",
      "profile_path": "/dI8bJxLVVQVrqYhgJoKbFI7YFyI.jpg"
    }
  ],
  "production_companies": [
    {
      "name": "DNA Films",
      "logo_path": "/vB7gY7zXXqZwNlXvzCDqFyBCrJZ.png"
    }
  ],
  "external_links": {
    "tmdb_url": "https://www.themoviedb.org/movie/1100988-28-years-later",
    "homepage": null,
    "imdb_id": "tt10804786"
  }
}
```

### 2. Rich Data Display Component

Create a reusable **Rich Content Display** component that can render detailed information from any external API:

**For TMDB Movies:**
- 🎭 **Hero Section**: Large backdrop image with title overlay
- 📋 **Info Panel**: Release date, runtime, genres, rating
- 🎬 **Cast Gallery**: Scrollable actor cards with images and character names
- 📝 **Synopsis**: Full movie overview
- 🔗 **External Links**: Links to TMDB page, IMDb, official site
- 🏢 **Production Info**: Companies, budget, revenue (if available)

**Visual Layout Example:**
```
┌─────────────────────────────────────────────────────────────┐
│                 [BACKDROP IMAGE]                            │
│                                                             │
│  ┌─[POSTER]─┐  ┌─────────────────────────────────────────┐ │
│  │          │  │ 28 Years Later (2025)                   │ │
│  │          │  │ ⭐ 8.5/10 │ 🕐 120 min │ 🎬 Horror      │ │
│  │          │  │                                         │ │
│  └──────────┘  │ It's been almost three decades since... │ │
│                └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Cast & Crew                                                 │
│ ┌─[ACTOR1]─┐ ┌─[ACTOR2]─┐ ┌─[ACTOR3]─┐ ┌─[DIRECTOR]─┐      │
│ │          │ │          │ │          │ │           │      │
│ │          │ │          │ │          │ │           │      │
│ │ Actor 1  │ │ Actor 2  │ │ Actor 3  │ │ Director  │      │
│ │ as Role  │ │ as Role  │ │ as Role  │ │           │      │
│ └──────────┘ └──────────┘ └──────────┘ └───────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### 3. Extensible Architecture

Design the system to easily support future APIs:

**Generic API Integration Pattern:**
```elixir
# New behaviour for rich data providers
defmodule EventasaurusWeb.Services.RichDataProviderBehaviour do
  @callback get_rich_data(source_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_display_config() :: map()
end

# TMDB implementation
defmodule EventasaurusWeb.Services.TmdbRichDataProvider do
  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour
  
  def get_rich_data(movie_id) do
    # Fetch detailed movie data from TMDB
  end
  
  def get_display_config() do
    %{
      type: :movie,
      hero_image_field: :backdrop_path,
      title_field: :title,
      sections: [
        %{name: "Overview", fields: [:overview]},
        %{name: "Cast", type: :gallery, field: :cast},
        %{name: "Details", fields: [:release_date, :runtime, :genres]}
      ]
    }
  end
end
```

### 4. User Interface Flow

**Enhanced Event Creation/Editing:**

1. **Image Selection**: User selects image from TMDB as currently implemented
2. **Rich Data Option**: New button appears: "Import Movie Details" 
3. **Preview Modal**: Shows what data will be imported with preview
4. **Confirmation**: User confirms import
5. **Auto-Population**: Event form fields populated with TMDB data
6. **Rich Display**: New expandable section shows rich movie information

**UI Components Needed:**

```elixir
# New LiveView component
defmodule EventasaurusWeb.Components.RichDataDisplay do
  use EventasaurusWeb, :live_component
  
  # Props: external_data, display_config
  # Renders different layouts based on data source
end

# Enhanced image picker modal
defmodule EventasaurusWeb.Components.ImagePickerModal do
  # Add "Import Rich Data" button when TMDB image selected
  # Add preview functionality
end
```

### 5. Database Schema Updates

**Enhanced Event Model:**
```elixir
# Add new field to events table
alter table(:events) do
  add :rich_external_data, :map, default: %{}
end

# Update Event schema
field :rich_external_data, :map, default: %{}
```

## Implementation Plan

### Phase 1: Core Architecture (Week 1-2)
- [ ] Create `RichDataProviderBehaviour` interface
- [ ] Implement `TmdbRichDataProvider` 
- [ ] Add database migration for `rich_external_data`
- [ ] Create basic `RichDataDisplay` component

### Phase 2: TMDB Integration (Week 2-3)
- [ ] Implement detailed TMDB API calls (cast, crew, images)
- [ ] Create TMDB-specific display templates
- [ ] Add "Import Movie Details" UI to image picker
- [ ] Implement rich data preview modal

### Phase 3: Event Integration (Week 3-4)
- [ ] Update event creation/editing to support rich data import
- [ ] Auto-populate event fields from TMDB data
- [ ] Add rich data display section to event show page
- [ ] Implement rich data management (edit, remove)

### Phase 4: Polish & Testing (Week 4-5)
- [ ] Add comprehensive tests for all new functionality
- [ ] Implement error handling and fallbacks
- [ ] Add loading states and animations
- [ ] Performance optimization for large datasets

### Phase 5: Future API Support (Week 5+)
- [ ] Documentation for adding new API providers
- [ ] Example implementation for additional API (e.g., Spotify for music events)
- [ ] Admin interface for managing API integrations

## Technical Considerations

### API Rate Limiting
- Implement caching for frequently accessed movie data
- Add request throttling for TMDB API calls
- Store detailed data locally to reduce API calls

### Data Freshness
- Consider TTL for cached rich data
- Provide "Refresh Data" option for event organizers
- Handle API deprecation gracefully

### Performance
- Lazy load rich data displays
- Implement image optimization for actor/poster images
- Add pagination for large cast lists

### Security
- Validate and sanitize all external API data
- Implement proper error handling for malformed responses
- Add rate limiting for rich data requests

## Future Enhancements

### Additional APIs to Consider:
- **Spotify API**: For music events (artist info, albums, tracks)
- **YouTube API**: For video content, trailers, interviews
- **Wikipedia API**: For detailed background information
- **OpenLibrary API**: For book-related events
- **Eventbrite API**: For event templates and suggestions

### Advanced Features:
- **AI-Powered Descriptions**: Generate event descriptions from rich data
- **Smart Recommendations**: Suggest related events based on rich data
- **Social Media Integration**: Auto-generate social media posts from rich data
- **Analytics**: Track which rich data elements drive the most engagement

## Success Metrics

- **User Adoption**: % of events using rich data integration
- **Time Savings**: Reduced time for event creation with pre-populated data
- **User Satisfaction**: Feedback on rich data displays
- **API Usage**: Monitoring API call efficiency and caching effectiveness

## Risk Assessment

### Low Risk:
- Database schema changes (additive only)
- New UI components (non-breaking)

### Medium Risk:
- API rate limiting and quotas
- Complex data transformation logic

### High Risk:
- Performance impact on event loading
- External API availability and reliability

## Conclusion

This feature will significantly enhance the event creation experience by leveraging the rich data already available from external APIs. The extensible architecture ensures that additional APIs can be easily integrated in the future, making this a scalable solution for comprehensive event enhancement.

The implementation focuses on user experience while maintaining system performance and reliability. The modular approach allows for incremental development and testing, reducing overall project risk.