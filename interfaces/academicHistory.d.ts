// interfaces/academicHistory.d.ts
export interface CourseGrades {
  terms: string;
  finalGrade: string;
  sm1: string; // Semester 1
  sm2: string; // Semester 2
  pr1: string; pr2: string; pr3: string; pr4: string; // Progress Reports
  pr5: string; pr6: string; pr7: string; pr8: string;
  rc1: string; rc2: string; rc3: string; rc4: string; // Report Cards
  ex1: string; ex2: string; // Exams
}

export interface AcademicYear {
  grade: number;
  courses: { [courseName: string]: CourseGrades };
}

export interface AcademicHistoryData {
  [academicYear: string]: AcademicYear; // e.g., "2023-2024": { grade: 12, courses: {...} }
  alt?: { [academicYear: string]: AcademicYear }; // Alternative courses
}

export interface AcademicHistoryResponse {
  success: boolean;
  data?: AcademicHistoryData;
  error?: string;
}
