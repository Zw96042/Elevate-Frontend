// utils/academicHistoryProcessor.tsx

interface CourseData {
  terms: string;
  finalGrade: string;
  sm1: string;
  sm2: string;
  pr1: string;
  pr2: string;
  pr3: string;
  pr4: string;
  pr5: string;
  pr6: string;
  pr7: string;
  pr8: string;
  rc1: string;
  rc2: string;
  rc3: string;
  rc4: string;
  ex1: string;
  ex2: string;
}

interface YearData {
  grade: number;
  courses: Record<string, CourseData>;
}

interface AcademicHistoryData {
  [year: string]: YearData;
  alt?: any; // We'll ignore this
}

interface GPAData {
  unweighted: number;
  weighted: number;
}

// === Course Level Detection (copied from gpaCalculator.tsx) ===

const apExceptions = new Set([
  "multivariable calculus", 
  "linear algebra",
  "stats 2: beyond ap statistics",
  "computer science 2",
  "computer science ii",
  "computer science 3",
  "computer science iii",
  "computer science ind study 1",
  "organic chemistry",
  "art historical methods",
  "art historical methods 2",
  "chinese 5 advanced",
  "chinese 6 advanced",
  "french 5 advanced",
  "french 6 advanced",
  "german 5 advanced",
  "german 6 advanced",
  "latin 5 advanced",
  "latin 6 advanced",
  "heritage, and immersion students",
  "spanish 6"
]);

const honorsExceptions = new Set([
  "editorial leadership 1, 2, and 3",
  "anatomy & physiology",
  "mentorship",
  "health science clinical",
  "practicum in health science - pharmacy or phlebotomy",
  "robotics 2",
  "robotics ii",
  "robotics 3",
  "robotics iii",
  "swift coding",
  "business incubator",
  "business acceleratoredu",
  "anatomy and physiology",
  "engineering"
]);

// Helper function to convert Roman numerals to numbers and vice versa
function normalizeNumbers(text: string): string {
  const romanToNumber: { [key: string]: string } = {
    ' i': ' 1', ' ii': ' 2', ' iii': ' 3', ' iv': ' 4', ' v': ' 5', ' vi': ' 6'
  };
  const numberToRoman: { [key: string]: string } = {
    ' 1': ' i', ' 2': ' ii', ' 3': ' iii', ' 4': ' iv', ' 5': ' v', ' 6': ' vi'
  };
  
  let normalized = text;
  // Convert Roman numerals to numbers
  Object.entries(romanToNumber).forEach(([roman, number]) => {
    normalized = normalized.replace(new RegExp(roman, 'gi'), number);
  });
  // Also try converting numbers to Roman numerals for comparison
  Object.entries(numberToRoman).forEach(([number, roman]) => {
    normalized = normalized.replace(new RegExp(number, 'gi'), roman);
  });
  
  return normalized;
}

function getCourseLevel(className: string): "AP" | "Honors" | "Regular" {
  if (!className || typeof className !== 'string' || className.trim() === '') {
    return "Regular";
  }
  
  const normalized = className.toLowerCase().trim();

  // First check for explicit AP pattern
  const hasAPKeyword = /\bap\b/.test(normalized);
  
  // Check AP exceptions - look for exact matches or close matches with Roman numeral normalization
  let matchedAPException = null;
  const isAPException = [...apExceptions].some(ex => {
    const normalizedCourse = normalizeNumbers(normalized);
    const normalizedEx = normalizeNumbers(ex);
    
    // Exact match (direct or after normalization)
    if (normalized === ex || normalizedCourse === normalizedEx) {
      matchedAPException = ex;
      return true;
    }
    
    // For longer exception names, check if course name contains the full exception
    if (ex.length > 10 && (normalized.includes(ex) || normalizedCourse.includes(normalizedEx))) {
      matchedAPException = ex;
      return true;
    }
    
    // For shorter exception names, be more strict - only match if they are very similar
    // Don't match partial course names like "computer science" with "computer science 2"
    if (ex.length <= 10 && normalized.length > 5) {
      // Split into words and check for meaningful overlap
      const courseWords = normalizedCourse.split(/\s+/);
      const exWords = normalizedEx.split(/\s+/);
      
      // For courses like "computer science i" vs "computer science 2", they need to match more precisely
      if (courseWords.length >= 2 && exWords.length >= 2) {
        // Both must have same base words and the level must match exactly
        const courseBase = courseWords.slice(0, -1).join(' ');
        const courseLevel = courseWords[courseWords.length - 1];
        const exBase = exWords.slice(0, -1).join(' ');
        const exLevel = exWords[exWords.length - 1];
        
        if (courseBase === exBase && courseLevel === exLevel) {
          matchedAPException = ex;
          return true;
        }
      } else {
        // Single word courses - use exact match only
        if (ex.includes(normalized) || normalizedEx.includes(normalizedCourse)) {
          matchedAPException = ex;
          return true;
        }
      }
    }
    
    return false;
  });
  
  if (hasAPKeyword || isAPException) return "AP";

  // Check for Honors pattern
  const hasHonorsKeyword = /\bhonors?\b/.test(normalized);
  
  // Check Honors exceptions with Roman numeral normalization
  let matchedHonorsException = null;
  const isHonorsException = [...honorsExceptions].some(ex => {
    const normalizedCourse = normalizeNumbers(normalized);
    const normalizedEx = normalizeNumbers(ex);
    
    // Exact match (direct or after normalization)
    if (normalized === ex || normalizedCourse === normalizedEx) {
      matchedHonorsException = ex;
      return true;
    }
    
    // For longer exception names, check if course name contains the full exception
    if (ex.length > 10 && (normalized.includes(ex) || normalizedCourse.includes(normalizedEx))) {
      matchedHonorsException = ex;
      return true;
    }
    
    // For shorter exception names, be more strict - only match if they are very similar
    // Don't match partial course names like "robotics" with "robotics 2"
    if (ex.length <= 10 && normalized.length > 5) {
      // Split into words and check for meaningful overlap
      const courseWords = normalizedCourse.split(/\s+/);
      const exWords = normalizedEx.split(/\s+/);
      
      // For courses like "robotics i" vs "robotics 2", they need to match more precisely
      if (courseWords.length >= 2 && exWords.length >= 2) {
        // Both must have same base word and the second word must match exactly
        const courseBase = courseWords[0];
        const courseLevel = courseWords[1];
        const exBase = exWords[0];
        const exLevel = exWords[1];
        
        if (courseBase === exBase && courseLevel === exLevel) {
          matchedHonorsException = ex;
          return true;
        }
      } else {
        // Single word courses - use exact match only
        if (ex.includes(normalized) || normalizedEx.includes(normalizedCourse)) {
          matchedHonorsException = ex;
          return true;
        }
      }
    }
    
    return false;
  });

  if (hasHonorsKeyword || isHonorsException) return "Honors";

  return "Regular";
}

// Helper function to check if a grade is valid (not empty, not "P", not "X")
const isValidGrade = (grade: string): boolean => {
  return !!grade && grade !== "" && grade !== "P" && grade !== "X" && !isNaN(Number(grade));
};

// Helper function to check if a course is scheduled for a specific term
const isCourseScheduledForTerm = (courseData: CourseData, termKey: string): boolean => {
  const terms = courseData.terms.toLowerCase();
  
  // Map term keys to their corresponding term numbers
  const termMapping: Record<string, number[]> = {
    'pr1': [1], 'pr2': [1],
    'pr3': [2], 'pr4': [2], 
    'pr5': [3], 'pr6': [3],
    'pr7': [4], 'pr8': [4],
    'rc1': [1], 'rc2': [2], 'rc3': [3], 'rc4': [4],
    'sm1': [1, 2], 'sm2': [3, 4]
  };
  
  const termNumbers = termMapping[termKey] || [];
  
  // Check if any of the term numbers for this key are in the course's terms
  return termNumbers.some(termNum => {
    return terms.includes(termNum.toString()) || 
           terms.includes(`${termNum} -`) || 
           terms.includes(`- ${termNum}`) ||
           terms.includes(`1 - ${termNum}`) ||
           (termNum <= 4 && (terms.includes('1 - 4') || terms.includes('1-4'))) ||
           (termNum >= 1 && termNum <= 2 && (terms.includes('1 - 2') || terms.includes('1-2'))) ||
           (termNum >= 3 && termNum <= 4 && (terms.includes('3 - 4') || terms.includes('3-4')));
  });
};

// Calculate GPA for a specific term across all courses for a given grade level
const calculateTermGPA = (coursesData: Record<string, CourseData>, termKey: string, gradeLevel: number): GPAData => {
  let totalPoints = 0;
  let totalWeightedPoints = 0;
  let totalCourses = 0;
  let hasScheduledCourses = false;

  Object.entries(coursesData).forEach(([courseKey, courseData]) => {
    const grade = courseData[termKey as keyof CourseData];
    // Extract the original class name (remove the year suffix)
    const className = courseKey.replace(/_\d{4}-\d{4}$/, '');
    
    // Always get the course level for all courses (not just ones with grades)
    const courseLevel = getCourseLevel(className);
    
    // Check if this course is scheduled for this term
    if (isCourseScheduledForTerm(courseData, termKey)) {
      hasScheduledCourses = true;
      
      // Only include courses that have actual valid grades in the GPA calculation
      if (isValidGrade(grade)) {
        const numericGrade = Number(grade);
        totalPoints += numericGrade;
        
        // Add appropriate weight based on course level
        let weightedGrade = numericGrade;
        
        if (courseLevel === "AP") {
          weightedGrade = numericGrade + 10;
        } else if (courseLevel === "Honors") {
          weightedGrade = numericGrade + 5;
        }
        
        totalWeightedPoints += Math.min(weightedGrade, 110);
        totalCourses++;
      }
    }
  });

  // If no courses are scheduled for this term, return 0 (term won't be included)
  if (!hasScheduledCourses) {
    return { unweighted: 0, weighted: 0 };
  }

  // If courses are scheduled but no grades yet, return 0 GPA (term will be included but with 0)
  if (totalCourses === 0) {
    return { unweighted: 0, weighted: 0 };
  }

  const result = {
    unweighted: parseFloat((totalPoints / totalCourses).toFixed(2)),
    weighted: parseFloat((totalWeightedPoints / totalCourses).toFixed(2))
  };

  return result;
};

// Process academic history data and return GPA data for all terms, filtered by grade level
export const processAcademicHistory = (academicData: AcademicHistoryData, targetGradeLevel?: number): Record<string, GPAData> => {
  const gpaData: Record<string, GPAData> = {};
  
  // Filter to only include grades 9-12 and exclude alt
  let validYears = Object.entries(academicData).filter(([year, data]) => {
    return year !== 'alt' && data.grade >= 9 && data.grade <= 12;
  });

  // If a specific grade level is requested, filter to only that grade
  if (targetGradeLevel !== undefined && targetGradeLevel >= 9 && targetGradeLevel <= 12) {
    validYears = validYears.filter(([year, data]) => data.grade === targetGradeLevel);
  }

  // Combine all courses from the filtered years
  const allCourses: Record<string, CourseData> = {};
  
  validYears.forEach(([year, yearData]) => {
    Object.entries(yearData.courses).forEach(([className, courseData]) => {
      // Only filter out courses with final grade of "P" (Pass/Fail)
      // Keep courses even if they have empty grades in individual terms
      if (courseData.finalGrade !== "P") {
        // Use a unique key that includes the year to avoid conflicts
        allCourses[`${className}_${year}`] = courseData;
      }
    });
  });

  // Calculate GPA for each term
  const terms = ['PR1', 'PR2', 'RC1', 'PR3', 'PR4', 'RC2', 'PR5', 'PR6', 'RC3', 'PR7', 'PR8', 'RC4', 'SM1', 'SM2'];
  
  terms.forEach(term => {
    gpaData[term] = calculateTermGPA(allCourses, term.toLowerCase(), targetGradeLevel || 0);
  });

  return gpaData;
};

// Get current grade level from academic history
export const getCurrentGradeLevel = (academicData: AcademicHistoryData): number => {
  const validYears = Object.entries(academicData).filter(([year, data]) => {
    const isValid = year !== 'alt' && data.grade >= 9 && data.grade <= 12;
    return isValid;
  });

  if (validYears.length === 0) {
    return 9;
  }

  const maxGrade = Math.max(...validYears.map(([, data]) => data.grade));
  return maxGrade;
};
