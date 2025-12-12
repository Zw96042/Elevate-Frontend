// Centralized API types

export interface SkywardSessionCodes {
  dwd: string;
  wfaacl: string;
  encses: string;
  'User-Type': string;
  sessionid: string;
}

export interface SkywardCredentials {
  username: string;
  password: string;
  baseURL: string;
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
}

export interface GradeInfoParams {
  stuId: string;
  corNumId: string;
  gbId: string;
  section: string;
  bucket: string;
  entityId?: string;
  track?: string;
  subjectId?: string;
  dialogLevel?: string;
  isEoc?: string;
  customUrl?: string;
}

export interface Assignment {
  date: string;
  name: string;
  grade: number | null;
  score: number | null;
  points: { earned: number; total: number } | null;
  meta: { type: string; note: string }[];
}

export interface GradeCategory {
  category: string;
  weight: number | null;
  adjustedWeight: number | null;
  assignments: Assignment[];
}

export interface GradeInfoResult {
  course: string;
  instructor: string;
  period: number | null;
  lit: {
    name: string;
    begin: string | null;
    end: string | null;
  };
  gradebook: GradeCategory[];
  score: number | null;
  grade: number | null;
}

export interface Message {
  className: string;
  content: string;
  date: string;
  from: string;
  messageRowId: string;
  subject: string;
}
