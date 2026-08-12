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
const getAcademicYearForDate = (date: Date): number =>
  date.getMonth() >= 7 ? date.getFullYear() : date.getFullYear() - 1;

export const getCurrentAcademicYear = (): number =>
  getAcademicYearForDate(new Date());

/**
 * Determines the current term based on the current date
 */
export const getCurrentTerm = (): TermLabel => getTermForDate(new Date());

/**
 * Gets the term that should be active for a specific date
 */
export const getTermForDate = (date: Date): TermLabel => {
  const academicYear = getAcademicYearForDate(date);

  for (const range of ACADEMIC_CALENDAR) {
    const startYear = range.start.month >= 7 ? academicYear : academicYear + 1;
    const endYear = range.end.month >= 7 ? academicYear : academicYear + 1;
    const startDate = new Date(startYear, range.start.month, range.start.day);
    const endDate = new Date(endYear, range.end.month, range.end.day, 23, 59, 59, 999);

    if (date >= startDate && date <= endDate) {
      return range.term;
    }
  }

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
