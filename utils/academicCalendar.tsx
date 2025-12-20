// Academic Calendar Configuration
// This file defines the academic year structure and term date ranges

export type TermLabel = 'Q1 Grades' | 'Q2 Grades' | 'SM1 Grade' | 'Q3 Grades' | 'Q4 Grades' | 'SM2 Grades';

export interface TermDateRange {
  term: TermLabel;
  start: { month: number; day: number }; // month is 0-indexed (0 = January)
  end: { month: number; day: number };
  description: string;
}

/**
 * Academic Calendar Configuration
 * 
 * Academic year typically runs from August to May/June of the following calendar year.
 * Dates can be customized here to match your school district's calendar.
 */
export const ACADEMIC_CALENDAR: TermDateRange[] = [
  {
    term: 'Q1 Grades',
    start: { month: 7, day: 15 }, // August 15
    end: { month: 9, day: 25 },   // October 25
    description: 'First Quarter'
  },
  {
    term: 'Q2 Grades',
    start: { month: 9, day: 26 }, // October 26
    end: { month: 11, day: 22 },  // December 22
    description: 'Second Quarter'
  },
  {
    term: 'SM1 Grade',
    start: { month: 11, day: 23 }, // December 23
    end: { month: 0, day: 8 },     // January 8 (next calendar year)
    description: 'First Semester (Winter Break/Exam Period)'
  },
  {
    term: 'Q3 Grades',
    start: { month: 0, day: 9 },   // January 9 (next calendar year)
    end: { month: 2, day: 15 },    // March 15 (next calendar year)
    description: 'Third Quarter'
  },
  {
    term: 'Q4 Grades',
    start: { month: 2, day: 16 },  // March 16 (next calendar year)
    end: { month: 4, day: 30 },    // May 30 (next calendar year)
    description: 'Fourth Quarter'
  },
  {
    term: 'SM2 Grades',
    start: { month: 5, day: 1 },   // June 1 (next calendar year)
    end: { month: 6, day: 31 },    // July 31 (next calendar year)
    description: 'Second Semester (Summer Break/Final Grades)'
  }
];

/**
 * Determines the current academic year based on the current date
 * Academic year starts in August and ends in July of the following calendar year
 */
export const getCurrentAcademicYear = (): number => {
  const now = new Date();
  const currentMonth = now.getMonth(); // 0-indexed
  
  if (currentMonth >= 7) { // August or later
    return now.getFullYear();
  } else { // January through July
    return now.getFullYear() - 1;
  }
};

/**
 * Determines the current term based on the current date
 */
export const getCurrentTerm = (): TermLabel => {
  const now = new Date();
  const academicYear = getCurrentAcademicYear();
  
  // Helper function to check if current date is within a range
  const isDateInRange = (range: TermDateRange) => {
    const startDate = new Date(academicYear, range.start.month, range.start.day);
    let endDate = new Date(academicYear, range.end.month, range.end.day);
    
    // Handle ranges that cross calendar years (like SM1 Grade and terms in spring)
    if (range.end.month < range.start.month || 
        (range.start.month >= 7 && range.end.month <= 6)) {
      endDate = new Date(academicYear + 1, range.end.month, range.end.day);
    }
    
    // Special handling for terms that start in the next calendar year
    if (range.start.month <= 6 && range.start.month < 7) {
      const adjustedStartDate = new Date(academicYear + 1, range.start.month, range.start.day);
      const adjustedEndDate = new Date(academicYear + 1, range.end.month, range.end.day);
      
      if (now >= adjustedStartDate && now <= adjustedEndDate) {
        return true;
      }
    }
    
    return now >= startDate && now <= endDate;
  };
  
  // Check if current date falls within any term range
  for (const range of ACADEMIC_CALENDAR) {
    if (isDateInRange(range)) {
      console.log(`📅 Current date ${now.toLocaleDateString()} falls in ${range.term} (${range.description})`);
      return range.term;
    }
  }
  
  // Fallback logic for dates not covered (summer break, etc.)
  const currentMonth = now.getMonth();
  if (currentMonth >= 6 && currentMonth <= 7) { // July - early August
    console.log('📅 Summer break detected, defaulting to Q1 Grades for upcoming academic year');
    return 'Q1 Grades';
  }
  
  // Default fallback
  console.log('📅 No specific term detected, defaulting to Q1 Grades');
  return 'Q1 Grades';
};

/**
 * Gets the term that should be active for a specific date
 */
export const getTermForDate = (date: Date): TermLabel => {
  const academicYear = getCurrentAcademicYear();
  
  // Helper function to check if given date is within a range
  const isDateInRange = (range: TermDateRange, checkDate: Date) => {
    const startDate = new Date(academicYear, range.start.month, range.start.day);
    let endDate = new Date(academicYear, range.end.month, range.end.day);
    
    // Handle ranges that cross calendar years
    if (range.end.month < range.start.month || 
        (range.start.month >= 7 && range.end.month <= 6)) {
      endDate = new Date(academicYear + 1, range.end.month, range.end.day);
    }
    
    // Special handling for terms that start in the next calendar year
    if (range.start.month <= 6 && range.start.month < 7) {
      const adjustedStartDate = new Date(academicYear + 1, range.start.month, range.start.day);
      const adjustedEndDate = new Date(academicYear + 1, range.end.month, range.end.day);
      
      if (checkDate >= adjustedStartDate && checkDate <= adjustedEndDate) {
        return true;
      }
    }
    
    return checkDate >= startDate && checkDate <= endDate;
  };
  
  // Check if date falls within any term range
  for (const range of ACADEMIC_CALENDAR) {
    if (isDateInRange(range, date)) {
      return range.term;
    }
  }
  
  // Default fallback
  return 'Q1 Grades';
};

/**
 * Gets all available terms in chronological order
 */
export const getAllTerms = (): TermLabel[] => {
  return ACADEMIC_CALENDAR.map(range => range.term);
};

/**
 * Gets the date range for a specific term
 */
export const getTermDateRange = (term: TermLabel): TermDateRange | undefined => {
  return ACADEMIC_CALENDAR.find(range => range.term === term);
};