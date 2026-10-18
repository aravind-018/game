export type GameType = 
  | 'how_well_do_you_know_me'
  | 'would_you_rather'
  | 'who_is_more_likely_to'
  | 'couple_quiz_battle'
  | 'same_time_challenge'
  | 'deep_questions';

export interface GameMetadata {
  id: GameType;
  title: string;
  tagline: string;
  description: string;
  icon: string;
  badge: string;
  color: string;
}

export interface Room {
  id: string;
  code: string;
  host_id: string;
  selected_game: GameType | null;
  status: 'waiting' | 'in_progress' | 'completed' | 'abandoned';
  max_participants: number;
  created_at: string;
  updated_at: string;
}

export interface Participant {
  id: string;
  room_id: string;
  user_id: string;
  display_name: string;
  is_host: boolean;
  role_slot: 1 | 2;
  connected_at: string;
  last_seen_at: string;
}

export interface GameSession {
  id: string;
  room_id: string;
  game_type: GameType;
  status: 'starting' | 'active' | 'round_review' | 'finished';
  current_round_index: number;
  total_rounds: number;
  settings: {
    round_timeout_seconds: number;
  };
  created_at: string;
  finished_at: string | null;
}

export interface GameRound {
  id: string;
  session_id: string;
  round_number: number;
  question_id: string | null;
  custom_question_id: string | null;
  prompt: string;
  options: string[] | null;
  correct_option_index: number | null;
  target_player_id: string | null;
  target_player_name: string | null;
  status: 'in_progress' | 'revealed' | 'completed';
  p1_submitted: boolean;
  p2_submitted: boolean;
  started_at: string;
  expires_at: string | null;
  revealed_at: string | null;
}

export interface PlayerAnswer {
  id: string;
  round_id: string;
  user_id: string;
  display_name: string;
  answer_text: string;
  partner_prediction: string | null;
  is_correct: boolean | null;
  points_awarded: number;
  submitted_at: string;
}

export interface Score {
  id: string;
  session_id: string;
  user_id: string;
  display_name: string;
  score: number;
  matches_count: number;
  updated_at: string;
}

export const GAMES_CATALOG: GameMetadata[] = [
  {
    id: 'how_well_do_you_know_me',
    title: 'How Well Do You Know Me?',
    tagline: 'Test how intimately you know each other’s tastes, secrets & quirks!',
    description: 'One partner answers a personal preference; the other guesses their answer. Reveal and discover how well your minds align!',
    icon: 'HeartHandshake',
    badge: 'Couples Favorite',
    color: 'from-pink-500 to-rose-600',
  },
  {
    id: 'would_you_rather',
    title: 'Would You Rather?',
    tagline: 'Hilarious, romantic, and tough dilemmas designed for lovers.',
    description: 'Both choose their favorite option in secret. Compare choices to see if your romance is built on matching wavelength or fun opposites!',
    icon: 'Sparkles',
    badge: 'Fun & Casual',
    color: 'from-amber-500 to-orange-600',
  },
  {
    id: 'who_is_more_likely_to',
    title: 'Who Is More Likely To?',
    tagline: 'The ultimate playful blame-game for quirky couple habits.',
    description: 'Pick who fits the habit best: You, your partner, or both! Watch the laughs unfold as your votes reveal what you really think.',
    icon: 'Users',
    badge: 'Playful Debate',
    color: 'from-purple-500 to-indigo-600',
  },
  {
    id: 'couple_quiz_battle',
    title: 'Couple Quiz Battle',
    tagline: 'Speed trivia celebrating world love stories, pop culture & science.',
    description: 'Compete head-to-head on timed trivia with speed bonuses. Find out who has the sharpest romantic memory and fastest fingers!',
    icon: 'Trophy',
    badge: 'Competitive',
    color: 'from-blue-500 to-cyan-600',
  },
  {
    id: 'same_time_challenge',
    title: 'Same-Time Challenge',
    tagline: 'Count down to zero and make your pick simultaneously!',
    description: 'No talking allowed! A fast-paced synchronization test where you try to make the exact same choice at the exact same moment.',
    icon: 'Zap',
    badge: 'High Energy',
    color: 'from-emerald-500 to-teal-600',
  },
  {
    id: 'deep_questions',
    title: 'Deep Questions',
    tagline: 'Heart-to-heart prompts for deep emotional intimacy and love.',
    description: 'Thoughtful vulnerability prompts designed to open up heartfelt feelings, cherished memories, and dreams for your future together.',
    icon: 'Flame',
    badge: 'Intimate & Soulful',
    color: 'from-rose-500 to-red-700',
  },
];
