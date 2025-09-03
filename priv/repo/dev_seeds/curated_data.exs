defmodule DevSeeds.CuratedData do
  @moduledoc """
  Curated, realistic data for seeding. No Lorem ipsum!
  This module provides real movie titles, restaurant names, games, and other
  meaningful data to make our seed data feel authentic and useful for testing.
  """

  @doc """
  Popular movies with real data for RCV polls and movie nights
  """
  def movies do
    [
      %{
        title: "The Shawshank Redemption",
        year: 1994,
        genre: "Drama",
        description: "Two imprisoned men bond over years, finding solace and eventual redemption through acts of common decency.",
        tmdb_id: 278,
        rating: 9.3
      },
      %{
        title: "The Godfather",
        year: 1972,
        genre: "Crime/Drama",
        description: "The aging patriarch of an organized crime dynasty transfers control of his clandestine empire to his reluctant son.",
        tmdb_id: 238,
        rating: 9.2
      },
      %{
        title: "The Dark Knight",
        year: 2008,
        genre: "Action/Crime",
        description: "When the menace known as the Joker wreaks havoc on Gotham, Batman must accept one of the greatest psychological tests.",
        tmdb_id: 155,
        rating: 9.0
      },
      %{
        title: "Inception",
        year: 2010,
        genre: "Action/Sci-Fi",
        description: "A thief who steals corporate secrets through dream-sharing technology is given the inverse task of planting an idea.",
        tmdb_id: 27205,
        rating: 8.8
      },
      %{
        title: "Pulp Fiction",
        year: 1994,
        genre: "Crime/Drama",
        description: "The lives of two mob hitmen, a boxer, and a pair of diner bandits intertwine in four tales of violence and redemption.",
        tmdb_id: 680,
        rating: 8.9
      },
      %{
        title: "Forrest Gump",
        year: 1994,
        genre: "Drama/Romance",
        description: "The story of Forrest Gump, a slow-witted but kind-hearted man who witnesses and influences several defining historical events.",
        tmdb_id: 13,
        rating: 8.8
      },
      %{
        title: "The Matrix",
        year: 1999,
        genre: "Action/Sci-Fi",
        description: "A computer hacker learns about the true nature of reality and his role in the war against its controllers.",
        tmdb_id: 603,
        rating: 8.7
      },
      %{
        title: "Interstellar",
        year: 2014,
        genre: "Sci-Fi/Drama",
        description: "A team of explorers travel through a wormhole in space in an attempt to ensure humanity's survival.",
        tmdb_id: 157336,
        rating: 8.6
      },
      %{
        title: "The Lord of the Rings: The Fellowship of the Ring",
        year: 2001,
        genre: "Adventure/Fantasy",
        description: "A hobbit and his companions set out on a journey to destroy the powerful One Ring and save Middle-earth.",
        tmdb_id: 120,
        rating: 8.8
      },
      %{
        title: "Fight Club",
        year: 1999,
        genre: "Drama",
        description: "An insomniac office worker and a soap salesman form an underground fight club that evolves into much more.",
        tmdb_id: 550,
        rating: 8.8
      },
      %{
        title: "Goodfellas",
        year: 1990,
        genre: "Crime/Drama",
        description: "The story of Henry Hill and his life in the mob, covering his relationship with wife Karen and partners Jimmy and Tommy.",
        tmdb_id: 769,
        rating: 8.7
      },
      %{
        title: "The Silence of the Lambs",
        year: 1991,
        genre: "Crime/Thriller",
        description: "A young FBI cadet must receive the help of an incarcerated cannibal killer to catch another serial killer.",
        tmdb_id: 274,
        rating: 8.6
      },
      %{
        title: "Schindler's List",
        year: 1993,
        genre: "Biography/Drama",
        description: "The story of German industrialist Oskar Schindler, who saved more than a thousand Jewish refugees during the Holocaust.",
        tmdb_id: 424,
        rating: 9.0
      },
      %{
        title: "The Prestige",
        year: 2006,
        genre: "Drama/Mystery",
        description: "Two stage magicians engage in competitive one-upmanship in an attempt to create the ultimate stage illusion.",
        tmdb_id: 1124,
        rating: 8.5
      },
      %{
        title: "Parasite",
        year: 2019,
        genre: "Thriller/Drama",
        description: "A poor family schemes to become employed by a wealthy family by infiltrating their household as unrelated professionals.",
        tmdb_id: 496243,
        rating: 8.5
      },
      %{
        title: "Whiplash",
        year: 2014,
        genre: "Drama/Music",
        description: "A promising young drummer enrolls at a competitive music conservatory where his dreams are mentored by an instructor who will stop at nothing.",
        tmdb_id: 244786,
        rating: 8.5
      },
      %{
        title: "The Grand Budapest Hotel",
        year: 2014,
        genre: "Adventure/Comedy",
        description: "The adventures of Gustave H, a legendary concierge, and Zero Moustafa, the lobby boy who becomes his most trusted friend.",
        tmdb_id: 120467,
        rating: 8.1
      },
      %{
        title: "Blade Runner 2049",
        year: 2017,
        genre: "Sci-Fi/Thriller",
        description: "A young blade runner's discovery of a long-buried secret leads him to track down former blade runner Rick Deckard.",
        tmdb_id: 335984,
        rating: 8.0
      },
      %{
        title: "Mad Max: Fury Road",
        year: 2015,
        genre: "Action/Adventure",
        description: "In a post-apocalyptic wasteland, Max teams up with Furiosa to flee from cult leader Immortan Joe and his army.",
        tmdb_id: 76341,
        rating: 8.1
      },
      %{
        title: "Dune",
        year: 2021,
        genre: "Sci-Fi/Adventure",
        description: "Paul Atreides unites with Chani and the Fremen while seeking revenge against the conspirators who destroyed his family.",
        tmdb_id: 438631,
        rating: 8.0
      }
    ]
  end

  @doc """
  Real restaurant names and types for foodie events
  """
  def restaurants do
    [
      %{
        name: "Luigi's Italian Kitchen",
        cuisine: "Italian",
        price: "$$",
        description: "Authentic Italian cuisine with homemade pasta and wood-fired pizzas. Family recipes passed down for generations.",
        specialties: ["Osso Buco", "Homemade Ravioli", "Tiramisu"]
      },
      %{
        name: "Sakura Sushi Bar",
        cuisine: "Japanese",
        price: "$$$",
        description: "Fresh sushi and sashimi prepared by master chefs. Omakase experience available.",
        specialties: ["Omakase", "Dragon Roll", "Chirashi Bowl"]
      },
      %{
        name: "El Mariachi Cantina",
        cuisine: "Mexican",
        price: "$",
        description: "Vibrant Mexican street food with handmade tortillas and fresh salsas. Great margaritas!",
        specialties: ["Street Tacos", "Mole Poblano", "Fresh Guacamole"]
      },
      %{
        name: "The French Laundry",
        cuisine: "French",
        price: "$$$$",
        description: "Fine dining French cuisine with seasonal tasting menus and extensive wine selection.",
        specialties: ["Oysters and Pearls", "Duck Confit", "Soufflé"]
      },
      %{
        name: "Bangkok Street Kitchen",
        cuisine: "Thai",
        price: "$$",
        description: "Authentic Thai street food favorites with bold flavors and fresh ingredients.",
        specialties: ["Pad Thai", "Green Curry", "Mango Sticky Rice"]
      },
      %{
        name: "The Brass Monkey",
        cuisine: "Gastropub",
        price: "$$",
        description: "Elevated pub fare with craft beers and creative cocktails. Great for groups!",
        specialties: ["Fish & Chips", "Wagyu Burger", "Scotch Eggs"]
      },
      %{
        name: "Nonna's Kitchen",
        cuisine: "Italian",
        price: "$$",
        description: "Cozy Italian trattoria with traditional recipes and warm hospitality.",
        specialties: ["Carbonara", "Veal Marsala", "Cannoli"]
      },
      %{
        name: "Golden Dragon",
        cuisine: "Chinese",
        price: "$$",
        description: "Szechuan and Cantonese specialties with dim sum brunch on weekends.",
        specialties: ["Peking Duck", "Xiaolongbao", "Mapo Tofu"]
      },
      %{
        name: "Athens Taverna",
        cuisine: "Greek",
        price: "$$",
        description: "Mediterranean flavors with fresh seafood and traditional Greek dishes.",
        specialties: ["Moussaka", "Grilled Octopus", "Baklava"]
      },
      %{
        name: "Bombay Spice House",
        cuisine: "Indian",
        price: "$$",
        description: "Aromatic Indian cuisine with tandoori specialties and vegetarian options.",
        specialties: ["Butter Chicken", "Biryani", "Samosas"]
      },
      %{
        name: "The Steakhouse",
        cuisine: "American",
        price: "$$$",
        description: "Prime cuts and classic steakhouse sides. Dry-aged beef and extensive wine list.",
        specialties: ["Ribeye", "Lobster Tail", "Caesar Salad"]
      },
      %{
        name: "Pho Saigon",
        cuisine: "Vietnamese",
        price: "$",
        description: "Authentic Vietnamese pho and banh mi in a casual setting.",
        specialties: ["Pho Tai", "Banh Mi", "Spring Rolls"]
      },
      %{
        name: "Barcelona Tapas Bar",
        cuisine: "Spanish",
        price: "$$",
        description: "Small plates and Spanish wines in a lively atmosphere. Perfect for sharing!",
        specialties: ["Patatas Bravas", "Jamón Ibérico", "Paella"]
      },
      %{
        name: "Seoul Kitchen",
        cuisine: "Korean",
        price: "$$",
        description: "Korean BBQ and traditional dishes with banchan. Cook your own meat at the table!",
        specialties: ["Korean BBQ", "Bibimbap", "Kimchi Jjigae"]
      },
      %{
        name: "The Breakfast Club",
        cuisine: "Brunch",
        price: "$$",
        description: "All-day breakfast and brunch favorites. Bottomless mimosas on weekends!",
        specialties: ["Eggs Benedict", "Chicken & Waffles", "Avocado Toast"]
      }
    ]
  end

  @doc """
  Board games and video games for game night events
  """
  def games do
    %{
      board_games: [
        %{
          name: "Settlers of Catan",
          players: "3-4",
          duration: "60-90 min",
          description: "Trade, build, and settle the island of Catan in this classic strategy game."
        },
        %{
          name: "Monopoly",
          players: "2-8",
          duration: "60-180 min",
          description: "Buy properties, build houses and hotels, and bankrupt your opponents!"
        },
        %{
          name: "Ticket to Ride",
          players: "2-5",
          duration: "30-60 min",
          description: "Collect train cards and claim railway routes across the country."
        },
        %{
          name: "Codenames",
          players: "4-8",
          duration: "15-30 min",
          description: "Team-based word association game. Give one-word clues to help your team find agents."
        },
        %{
          name: "Pandemic",
          players: "2-4",
          duration: "45-60 min",
          description: "Work together to save humanity from four deadly diseases spreading across the globe."
        },
        %{
          name: "Wingspan",
          players: "1-5",
          duration: "40-70 min",
          description: "Attract birds to your wildlife preserves in this beautiful engine-building game."
        },
        %{
          name: "Azul",
          players: "2-4",
          duration: "30-45 min",
          description: "Collect colored tiles to create beautiful patterns on your board."
        },
        %{
          name: "Splendor",
          players: "2-4",
          duration: "30 min",
          description: "Collect gems and develop your gem trade to attract nobles."
        },
        %{
          name: "Scythe",
          players: "1-5",
          duration: "90-120 min",
          description: "Lead your faction to victory in an alternate-history 1920s Europe."
        },
        %{
          name: "Cards Against Humanity",
          players: "4-20",
          duration: "30-90 min",
          description: "The party game for horrible people. Fill in the blanks with outrageous answers."
        }
      ],
      video_games: [
        %{
          name: "Mario Kart 8 Deluxe",
          platform: "Nintendo Switch",
          players: "1-4 local",
          description: "Race against friends in this chaotic kart racing game."
        },
        %{
          name: "Super Smash Bros. Ultimate",
          platform: "Nintendo Switch",
          players: "1-8 local",
          description: "Battle it out with Nintendo's all-star cast of characters."
        },
        %{
          name: "Overcooked 2",
          platform: "Multiple",
          players: "1-4 local",
          description: "Chaotic co-op cooking game that will test your friendships."
        },
        %{
          name: "Rocket League",
          platform: "Multiple",
          players: "1-4 local",
          description: "Soccer meets driving in this physics-based sports game."
        },
        %{
          name: "Among Us",
          platform: "Multiple",
          players: "4-10 online",
          description: "Find the impostor among your crewmates before it's too late!"
        },
        %{
          name: "Jackbox Party Pack",
          platform: "Multiple",
          players: "1-8 local",
          description: "Collection of party games playable with phones as controllers."
        },
        %{
          name: "Street Fighter 6",
          platform: "Multiple",
          players: "1-2 local",
          description: "Classic fighting game with new mechanics and characters."
        },
        %{
          name: "FIFA 24",
          platform: "Multiple",
          players: "1-4 local",
          description: "The latest in soccer simulation with updated rosters."
        },
        %{
          name: "Minecraft",
          platform: "Multiple",
          players: "1-4 local",
          description: "Build, explore, and survive in infinite procedurally generated worlds."
        },
        %{
          name: "It Takes Two",
          platform: "Multiple",
          players: "2 local",
          description: "Co-op adventure designed specifically for two players."
        }
      ]
    }
  end

  @doc """
  Concert and music event data
  """
  def concerts do
    [
      %{artist: "Taylor Swift", genre: "Pop", tour: "The Eras Tour"},
      %{artist: "Ed Sheeran", genre: "Pop/Folk", tour: "Mathematics Tour"},
      %{artist: "Beyoncé", genre: "R&B/Pop", tour: "Renaissance World Tour"},
      %{artist: "The Weeknd", genre: "R&B/Pop", tour: "After Hours Tour"},
      %{artist: "Coldplay", genre: "Alternative Rock", tour: "Music of the Spheres Tour"},
      %{artist: "Drake", genre: "Hip-Hop", tour: "It's All a Blur Tour"},
      %{artist: "Bruno Mars", genre: "Pop/R&B", tour: "24K Magic World Tour"},
      %{artist: "Billie Eilish", genre: "Alternative Pop", tour: "Happier Than Ever Tour"},
      %{artist: "Post Malone", genre: "Hip-Hop/Pop", tour: "Twelve Carat Tour"},
      %{artist: "Imagine Dragons", genre: "Alternative Rock", tour: "Mercury Tour"},
      %{artist: "Arctic Monkeys", genre: "Indie Rock", tour: "The Car Tour"},
      %{artist: "The Rolling Stones", genre: "Rock", tour: "Sixty Tour"},
      %{artist: "Metallica", genre: "Metal", tour: "M72 World Tour"},
      %{artist: "Foo Fighters", genre: "Rock", tour: "Everything or Nothing Tour"},
      %{artist: "Green Day", genre: "Punk Rock", tour: "Saviors Tour"}
    ]
  end

  @doc """
  Sports events and teams
  """
  def sports_events do
    [
      %{
        sport: "Basketball",
        home_team: "Lakers",
        away_team: "Warriors",
        venue: "Crypto.com Arena"
      },
      %{
        sport: "Football",
        home_team: "49ers",
        away_team: "Cowboys",
        venue: "Levi's Stadium"
      },
      %{
        sport: "Baseball",
        home_team: "Yankees",
        away_team: "Red Sox",
        venue: "Yankee Stadium"
      },
      %{
        sport: "Hockey",
        home_team: "Rangers",
        away_team: "Bruins",
        venue: "Madison Square Garden"
      },
      %{
        sport: "Soccer",
        home_team: "LA Galaxy",
        away_team: "Portland Timbers",
        venue: "Dignity Health Sports Park"
      }
    ]
  end

  @doc """
  Book club selections
  """
  def books do
    [
      %{
        title: "The Great Gatsby",
        author: "F. Scott Fitzgerald",
        genre: "Classic Fiction",
        description: "A portrait of the Jazz Age and the American Dream's dark side."
      },
      %{
        title: "1984",
        author: "George Orwell",
        genre: "Dystopian Fiction",
        description: "A totalitarian world where Big Brother watches everything."
      },
      %{
        title: "To Kill a Mockingbird",
        author: "Harper Lee",
        genre: "Classic Fiction",
        description: "A story of racial injustice and childhood innocence in the American South."
      },
      %{
        title: "The Midnight Library",
        author: "Matt Haig",
        genre: "Contemporary Fiction",
        description: "A library between life and death where every book is a life you could have lived."
      },
      %{
        title: "Project Hail Mary",
        author: "Andy Weir",
        genre: "Science Fiction",
        description: "An astronaut wakes up alone on a spaceship with no memory of how he got there."
      },
      %{
        title: "Educated",
        author: "Tara Westover",
        genre: "Memoir",
        description: "A woman's quest for knowledge leads her from a survivalist family to Cambridge."
      },
      %{
        title: "Where the Crawdads Sing",
        author: "Delia Owens",
        genre: "Mystery/Fiction",
        description: "A coming-of-age murder mystery set in the marshes of North Carolina."
      },
      %{
        title: "Atomic Habits",
        author: "James Clear",
        genre: "Self-Help",
        description: "How tiny changes can lead to remarkable results in building good habits."
      },
      %{
        title: "The Seven Husbands of Evelyn Hugo",
        author: "Taylor Jenkins Reid",
        genre: "Historical Fiction",
        description: "A Hollywood icon finally tells her scandalous life story."
      },
      %{
        title: "Dune",
        author: "Frank Herbert",
        genre: "Science Fiction",
        description: "Political intrigue and revolution on the desert planet Arrakis."
      }
    ]
  end

  @doc """
  Outdoor activities for hiking and adventure events
  """
  def outdoor_activities do
    [
      %{
        activity: "Hiking",
        trails: [
          "Eagle Rock Trail - 5 miles, moderate",
          "Sunset Peak - 8 miles, challenging",
          "River Walk Trail - 3 miles, easy",
          "Mountain View Loop - 6 miles, moderate",
          "Forest Canyon Trail - 10 miles, challenging"
        ]
      },
      %{
        activity: "Beach Day",
        locations: [
          "Santa Monica Beach",
          "Malibu Beach",
          "Venice Beach",
          "Manhattan Beach",
          "Hermosa Beach"
        ]
      },
      %{
        activity: "Camping",
        sites: [
          "Yosemite National Park",
          "Joshua Tree",
          "Big Sur",
          "Lake Tahoe",
          "Sequoia National Forest"
        ]
      },
      %{
        activity: "Rock Climbing",
        locations: [
          "Indoor Rock Gym - Beginner friendly",
          "Devil's Punchbowl - Intermediate",
          "Stoney Point - All levels",
          "Malibu Creek - Advanced",
          "Joshua Tree - All levels"
        ]
      }
    ]
  end

  @doc """
  Random event title generator using real data (no Lorem ipsum!)
  """
  def generate_realistic_event_title do
    templates = [
      fn -> "Movie Night: #{Enum.random(movies()).title}" end,
      fn -> "Dinner at #{Enum.random(restaurants()).name}" end,
      fn -> "Game Night: #{Enum.random(games().board_games).name}" end,
      fn -> "#{Enum.random(concerts()).artist} Concert" end,
      fn -> "#{Enum.random(sports_events()).home_team} vs #{Enum.random(sports_events()).away_team}" end,
      fn -> "Book Club: #{Enum.random(books()).title}" end,
      fn -> 
        hiking = Enum.find(outdoor_activities(), fn a -> a.activity == "Hiking" end)
        trail = Enum.random(hiking.trails)
        "Hiking: #{trail}"
      end,
      fn -> "Trivia Night at #{Enum.random(restaurants()).name}" end,
      fn -> "Wine Tasting at #{Enum.random(restaurants()).name}" end,
      fn -> "Birthday Party at #{Enum.random(["Bowling Alley", "Arcade", "Park", "Beach", "Rooftop"])}" end,
      fn -> "Karaoke Night" end,
      fn -> "Escape Room Adventure" end,
      fn -> "Paint and Sip" end,
      fn -> "Comedy Show" end,
      fn -> "Cooking Class: #{Enum.random(restaurants()).cuisine} Cuisine" end,
      fn -> "Beach Volleyball Tournament" end,
      fn -> "Board Game Cafe Meetup" end,
      fn -> "Farmers Market Tour" end,
      fn -> "Museum Visit: #{Enum.random(["Art", "Science", "History", "Natural History"])}" end,
      fn -> "Yoga in the Park" end
    ]
    
    Enum.random(templates).()
  end

  @doc """
  Generate a realistic event description based on the title
  """
  def generate_event_description(title) do
    cond do
      String.contains?(title, "Movie") ->
        movie = Enum.find(movies(), fn m -> String.contains?(title, m.title) end)
        if movie do
          """
          Join us for a screening of #{movie.title} (#{movie.year})!
          
          #{movie.description}
          
          Genre: #{movie.genre} | Rating: #{movie.rating}/10
          
          We'll have popcorn, snacks, and drinks. Feel free to bring your favorite movie snacks!
          Discussion afterwards for those interested.
          """
        else
          "Join us for an awesome movie night! Popcorn and drinks provided. Get ready for a great film and good company!"
        end
        
      String.contains?(title, "Dinner") || String.contains?(title, "Restaurant") ->
        restaurant = Enum.find(restaurants(), fn r -> String.contains?(title, r.name) end)
        if restaurant do
          """
          Let's gather for dinner at #{restaurant.name}!
          
          #{restaurant.description}
          
          Cuisine: #{restaurant.cuisine} | Price Range: #{restaurant.price}
          Must-try dishes: #{Enum.join(restaurant.specialties, ", ")}
          
          Please RSVP so we can make reservations. Separate checks available.
          """
        else
          "Join us for a delicious dinner! Great food, great company. RSVP for reservation count."
        end
        
      String.contains?(title, "Game") ->
        "Game night at my place! We'll have a variety of board games and video games. Bring your competitive spirit and your favorite snacks to share. All skill levels welcome!"
        
      String.contains?(title, "Concert") ->
        "Live music event! Get ready for an amazing performance. Tickets required. Let's enjoy great music together!"
        
      String.contains?(title, "Hiking") ->
        "Outdoor adventure time! Bring water, snacks, and appropriate footwear. We'll meet at the trailhead. All fitness levels welcome - we'll go at a comfortable pace for everyone."
        
      String.contains?(title, "Book Club") ->
        book = Enum.find(books(), fn b -> String.contains?(title, b.title) end)
        if book do
          """
          This month we're reading "#{book.title}" by #{book.author}.
          
          #{book.description}
          
          Genre: #{book.genre}
          
          Come ready to discuss themes, characters, and your favorite passages. Light refreshments provided.
          """
        else
          "Monthly book club meeting! Come ready to discuss this month's selection. New members always welcome!"
        end
        
      String.contains?(title, "Birthday") ->
        "Come celebrate with us! There will be cake, games, and good times. No gifts necessary - your presence is the present!"
        
      String.contains?(title, "Trivia") ->
        "Test your knowledge at trivia night! Teams of 4-6 people. Prizes for the top 3 teams. Categories include general knowledge, pop culture, history, science, and sports."
        
      String.contains?(title, "Wine Tasting") ->
        "Join us for an evening of wine tasting! We'll sample a variety of wines paired with cheese and appetizers. Both wine enthusiasts and beginners welcome!"
        
      String.contains?(title, "Karaoke") ->
        "Karaoke night! Sing your heart out or just come to cheer on friends. Song list available, or bring your own backing tracks. No judgment zone - just fun!"
        
      true ->
        "Join us for a fun gathering! Looking forward to seeing everyone there. Please RSVP so we can plan accordingly."
    end
  end

  @doc """
  Get random tagline for an event
  """
  def random_tagline do
    [
      "Let's make memories!",
      "Don't miss out!",
      "Fun times ahead!",
      "Save the date!",
      "You're invited!",
      "Join the fun!",
      "See you there!",
      "Can't wait!",
      "It's going to be great!",
      "Mark your calendar!",
      "RSVP now!",
      "Limited spots available!",
      "Bring your friends!",
      "All are welcome!",
      "Free admission!",
      "Food & drinks provided!",
      "Family friendly!",
      "21+ only",
      "Casual attire",
      "Semi-formal event"
    ]
    |> Enum.random()
  end
end