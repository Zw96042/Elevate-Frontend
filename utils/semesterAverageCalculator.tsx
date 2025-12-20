// utils/semesterAverageCalculator.tsx

/**
 * Calculates semester averages from RC (Report Card) grades with proper rounding
 * RC grades are rounded to the nearest whole number before calculating semester averages
 */

export interface SemesterAverageResult {
  sm1: number | null; // Semester 1 average (from RC1 and RC2)
  sm2: number | null; // Semester 2 average (from RC3 and RC4)
}

/**
 * Calculate semester averages from RC grades
 * @param rc1 - Report Card 1 grade (string or number)
 * @param rc2 - Report Card 2 grade (string or number)  
 * @param rc3 - Report Card 3 grade (string or number)
 * @param rc4 - Report Card 4 grade (string or number)
 * @returns Object with sm1 and sm2 averages
 */
export function calculateSemesterAverages(
  rc1: string | number | null | undefined,
  rc2: string | number | null | undefined,
  rc3: string | number | null | undefined,
  rc4: string | number | null | undefined
): SemesterAverageResult {
  
  // Helper function to parse and round RC grades
  const parseAndRoundRC = (grade: string | number | null | undefined): number | null => {
    if (grade === null || grade === undefined || grade === '' || grade === 'P' || grade === 'X') {
      return null;
    }
    
    const numericGrade = typeof grade === 'string' ? parseFloat(grade) : grade;
    
    if (isNaN(numericGrade)) {
      return null;
    }
    
    // Round RC grade to nearest whole number as specified
    return Math.round(numericGrade);
  };
  
  // Parse and round all RC grades
  const roundedRC1 = parseAndRoundRC(rc1);
  const roundedRC2 = parseAndRoundRC(rc2);
  const roundedRC3 = parseAndRoundRC(rc3);
  const roundedRC4 = parseAndRoundRC(rc4);
  
  // Calculate Semester 1 average (RC1 + RC2) / 2
  let sm1: number | null = null;
  if (roundedRC1 !== null && roundedRC2 !== null) {
    sm1 = (roundedRC1 + roundedRC2) / 2;
  } else if (roundedRC1 !== null) {
    sm1 = roundedRC1; // Use RC1 if RC2 is missing
  } else if (roundedRC2 !== null) {
    sm1 = roundedRC2; // Use RC2 if RC1 is missing
  }
  
  // Calculate Semester 2 average (RC3 + RC4) / 2
  let sm2: number | null = null;
  if (roundedRC3 !== null && roundedRC4 !== null) {
    sm2 = (roundedRC3 + roundedRC4) / 2;
  } else if (roundedRC3 !== null) {
    sm2 = roundedRC3; // Use RC3 if RC4 is missing
  } else if (roundedRC4 !== null) {
    sm2 = roundedRC4; // Use RC4 if RC3 is missing
  }
  
  return {
    sm1,
    sm2
  };
}

/**
 * Update course data with calculated semester averages
 * @param courseData - Course data object with RC grades
 * @returns Updated course data with calculated SM1 and SM2
 */
export function updateCourseWithSemesterAverages<T extends {
  rc1?: string | number;
  rc2?: string | number;
  rc3?: string | number;
  rc4?: string | number;
  sm1?: string | number | null;
  sm2?: string | number | null;
}>(courseData: T): T {
  
  const averages = calculateSemesterAverages(
    courseData.rc1,
    courseData.rc2,
    courseData.rc3,
    courseData.rc4
  );
  
  return {
    ...courseData,
    sm1: averages.sm1,
    sm2: averages.sm2
  };
}

/**
 * Batch update multiple courses with calculated semester averages
 * @param courses - Array of course data objects
 * @returns Array of updated course data with calculated semester averages
 */
export function updateCoursesWithSemesterAverages<T extends {
  rc1?: string | number;
  rc2?: string | number;
  rc3?: string | number;
  rc4?: string | number;
  sm1?: string | number | null;
  sm2?: string | number | null;
}>(courses: T[]): T[] {
  
  return courses.map(course => updateCourseWithSemesterAverages(course));
}