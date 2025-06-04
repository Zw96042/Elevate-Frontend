interface Movie {
  id: number;
  title: string;
  adult: boolean;
  backdrop_path: string;
  genre_ids: number[];
  original_language: string;
  original_title: string;
  overview: string;
  popularity: number;
  poster_path: string;
  release_date: string;
  video: boolean;
  vote_average: number;
  vote_count: number;
}


interface Message {
  className: string;
  subject: string;
  from: string;
  date: string;
  content: string;
}

interface Class {
  name: string;
  teacher: string;
  t1: {
        categories: {
            names: string[];
            grades: number[];
        };
        total: number;
    };
  t2: {
        categories: {
            names: string[];
            grades: number[];
        };
        total: number;
    };
  s1: {
        categories: {
            names: string[];
            grades: number[];
        };
        total: number;
    };
  t3: {
        categories: {
            names: string[];
            grades: number[];
        };
        total: number;
    };
  t4: {
        categories: {
            names: string[];
            grades: number[];
        };
        total: number;
    };
  s2: {
        categories: {
            names: string[];
            grades: number[];
        };
        total: number;
    };
}

interface Assignment {
  className: string;
  name: string;
  category: string;
  grade: number;
  outOf: number;
  dueDate: string;
}


interface TrendingMovie {
  searchTerm: string;
  movie_id: number;
  title: string;
  count: number;
  poster_url: string;
}

interface MovieDetails {
  adult: boolean;
  backdrop_path: string | null;
  belongs_to_collection: {
    id: number;
    name: string;
    poster_path: string;
    backdrop_path: string;
  } | null;
  budget: number;
  genres: {
    id: number;
    name: string;
  }[];
  homepage: string | null;
  id: number;
  imdb_id: string | null;
  original_language: string;
  original_title: string;
  overview: string | null;
  popularity: number;
  poster_path: string | null;
  production_companies: {
    id: number;
    logo_path: string | null;
    name: string;
    origin_country: string;
  }[];
  production_countries: {
    iso_3166_1: string;
    name: string;
  }[];
  release_date: string;
  revenue: number;
  runtime: number | null;
  spoken_languages: {
    english_name: string;
    iso_639_1: string;
    name: string;
  }[];
  status: string;
  tagline: string | null;
  title: string;
  video: boolean;
  vote_average: number;
  vote_count: number;
}

interface TrendingCardProps {
  movie: TrendingMovie;
  index: number;
}
