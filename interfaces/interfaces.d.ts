// ===== AUTHENTICATION & SESSION TYPES =====
export interface SkywardAuthInfo {
  link: string;
  username: string;
  password: string;
}

export interface SkywardSessionCodes {
  dwd: string;
  wfaacl: string;
  encses: string;
  sessionid: string;
  'User-Type': string;
}

export interface SkywardLoginParams {
  username: string;
  password: string;
  baseURL: string;
}

export interface AuthResult {
  success: boolean;
  error?: string;
}

// ===== API RESPONSE TYPES =====
export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface ApiError {
  message: string;
  status?: number;
  code?: string;
}

// ===== TERM & GRADE TYPES =====
export type TermLabel = 
  | "Q1 Grades" 
  | "Q2 Grades" 
  | "SM1 Grade" 
  | "Q3 Grades" 
  | "Q4 Grades" 
  | "SM2 Grades";

export type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';
export type CourseLevel = "AP" | "Honors" | "Regular";

export interface TermData {
  categories: {
    names: string[];
    weights: number[];
  };
  total: number;
}

// ===== CLASS & COURSE TYPES =====
export interface Class {
  name: string;
  teacher: string;
  corNumId: string;
  stuId: string;
  section: string;
  gbId: string;
  t1: TermData;
  t2: TermData;
  s1: TermData;
  t3: TermData;
  t4: TermData;
  s2: TermData;
  stuId?: string;
  corNumId?: string;
  section?: string;
  gbID?: string;
}

export interface CourseData {
  courseName: string;
  subjectArea: string;
  teacher: string;
  gradeLevel: number;
  credits: number;
  currentScores: Record<string, { score: number }>;
}

export interface UnifiedCourseData {
  courseId: number;
  stuId: string;
  section: string;
  gbId: string;
  courseName: string;
  instructor: string | null;
  period: number | null;
  time: string | null;
  semester: 'fall' | 'spring' | 'both' | 'unknown';
  termLength: string;
  gradeYear?: number;
  currentScores: Array<{ bucket: string; score: number }>;
  historicalGrades: {
    pr1?: string;
    pr2?: string;
    rc1?: string;
    pr3?: string;
    pr4?: string;
    rc2?: string;
    pr5?: string;
    pr6?: string;
    rc3?: string;
    pr7?: string;
    pr8?: string;
    rc4?: string;
    sm1?: string;
    sm2?: string;
    finalGrade?: string;
  };
}

// ===== ASSIGNMENT TYPES =====
export interface Assignment {
  id?: string;
  className: string;
  name: string;
  term: string;
  category: string;
  grade: string;
  outOf: number;
  dueDate: string;
  artificial: boolean;
  meta?: AssignmentMeta[];
}

export interface AssignmentMeta {
  type: 'missing' | 'noCount' | 'absent';
  note: string;
}

export interface AssignmentCardProps extends Assignment {
  onPress?: () => void;
  showClass?: boolean;
}

// ===== MESSAGE TYPES =====
export interface Message {
  className: string;
  messageRowId: string;
  subject: string;
  from: string;
  date: string;
  content: string;
}

// ===== GPA & ACADEMIC HISTORY TYPES =====
export interface GPAData {
  gpa: number;
  credits: number;
  unweighted?: number;
  weighted?: number;
}

export interface CourseGrades {
  terms: string;
  finalGrade: string;
  sm1: string;
  sm2: string;
  pr1: string; pr2: string; pr3: string; pr4: string;
  pr5: string; pr6: string; pr7: string; pr8: string;
  rc1: string; rc2: string; rc3: string; rc4: string;
  ex1: string; ex2: string;
}

export interface AcademicYear {
  grade: number;
  courses: { [courseName: string]: CourseGrades };
}

export interface AcademicHistoryData {
  [academicYear: string]: AcademicYear;
  alt?: { [academicYear: string]: AcademicYear };
}

export interface AcademicHistoryResponse extends ApiResponse<AcademicHistoryData> {}

export interface ReportCardResult extends ApiResponse {
  courses?: Course[];
}

export interface Course {
  course: number;
  courseName: string;
  instructor: string | null;
  period: number | null;
  time: string | null;
  scores: Array<{ bucket: string; score: number }>;
}

export interface CachedAcademicData {
  data: AcademicHistoryData;
  timestamp: number;
}

export interface YearData {
  [courseName: string]: CourseData;
}

// ===== CONTEXT TYPES =====
export interface UnifiedDataContextType {
  coursesData: UnifiedCourseData[] | null;
  setCoursesData: React.Dispatch<React.SetStateAction<UnifiedCourseData[] | null>>;
  loading: boolean;
  error: string | null;
  refreshCourses: (force?: boolean) => Promise<void>;
}

export interface UnifiedDataResult {
  success: boolean;
  courses?: UnifiedCourseData[];
  error?: string;
  lastUpdated?: string;
  requiresLogin?: boolean;
}

export interface UnifiedGPAResult {
  success: boolean;
  gpa?: GPAData;
  rawCourses?: UnifiedCourseData[];
  currentGradeLevel?: number;
  availableGradeLevels?: number[];
  error?: string;
  lastUpdated?: string;
}

// ===== MODAL & SHEET TYPES =====
export interface ModalData {
  selectedClass: string;
  selectedTeacher: string;
  corNumId: string;
  stuId: string;
  section: string;
  gbId: string;
  termData: TermData;
  selectedTerm: TermLabel;
  selectedCategory: string;
  categories: string[];
}

export interface AddAssignmentSheetContextType {
  isVisible: boolean;
  showSheet: (data: ModalData) => void;
  hideSheet: () => void;
  modalData: ModalData | null;
  addSheetRef: React.RefObject<any>;
}

export interface AddClassSheetContextType {
  isVisible: boolean;
  showSheet: (data: ModalData) => void;
  hideSheet: () => void;
  modalData: ModalData | null;
  addClassRef: React.RefObject<any>;
}

// ===== API CLIENT TYPES =====
export interface GradeInfoParams {
  dwd: string;
  wfaacl: string;
  encses: string;
  sessionid: string;
  baseUrl: string;
  userType: string;
  corNumId: string;
  stuId: string;
  section: string;
  gbId: string;
}

export interface GradeInfoResult extends ApiResponse {
  data?: any;
}

export interface AcademicHistoryResult extends ApiResponse {
  data?: AcademicHistoryData;
}

export interface ReportCardResult extends ApiResponse {
  data?: any;
}

// ===== PROP TYPES =====
export interface GpaCardProps {
  gpaData: GPAData;
  gradeLevel: GradeLevel;
}

export interface ClassCardProps extends Class {
  term: TermLabel;
}

// ===== UTILITY TYPES =====
export type AsyncStorageKeys = 
  | 'dwd' 
  | 'wfaacl' 
  | 'encses' 
  | 'User-Type' 
  | 'sessionid' 
  | 'baseUrl'
  | 'artificialAssignments'
  | 'academicHistory'
  | 'currentGradeLevel';

export interface CacheItem<T> {
  data: T;
  timestamp: number;
  ttl?: number; // Time to live in milliseconds
}

export interface ErrorWithDetails extends Error {
  status?: number;
  code?: string;
  details?: any;
}