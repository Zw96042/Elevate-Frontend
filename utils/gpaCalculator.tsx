export type SavedClass = {
  className: string;
  sm1: number;
  sm2: number;
  rc1?: number;
  rc2?: number;
  rc3?: number;
  rc4?: number;
};

export type GPAResult = {
  unweighted: number;
  weighted: number;
};

export type PeriodicGPA = {
  fall: GPAResult;
  spring: GPAResult;
};

// === ✳️ Define your exceptions ===

const apExceptions = new Set([
  "Multivariable Calculus", 
  "Linear Algebra",
  "Stats 2: Beyond AP Statistics",
  "Computer Science 2",
  "Computer Science II",
  "Computer Science 3",
  "Computer Science III",
  "Computer Science Ind Study 1",
  "Organic Chemistry",
  "Art Historical Methods",
  "Art Historical Methods 2",
  "Chinese 5 Advanced",
  "Chinese 6 Advanced",
  "French 5 Advanced",
  "French 6 Advanced",
  "German 5 Advanced",
  "German 6 Advanced",
  "Latin 5 Advanced",
  "Latin 6 Advanced",
  "Heritage, and Immersion Students",
  "Spanish 6"
]);

const honorsExceptions = new Set([
  "Editorial Leadership 1, 2, and 3",
  "Anatomy & Physiology ",
  "Mentorship",
  "Health Science Clinical",
  "Practicum in Health Science - Pharmacy or Phlebotomy",
  "Robotics 2",
  "Robotics II",
  "Robotics 3",
  "Robotics III",
  "Swift Coding",
  "Business Incubator",
  "Business ACCeleratoredu",
  "Anatomy and Physiology",
  "Engineering"
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
  const isAPException = [...apExceptions].some(ex => {
    const exLower = ex.toLowerCase().trim();
    const normalizedCourse = normalizeNumbers(normalized);
    const normalizedEx = normalizeNumbers(exLower);
    
    // Exact match (direct or after normalization)
    if (normalized === exLower || normalizedCourse === normalizedEx) return true;
    
    // For longer exception names, check if course name contains the full exception
    if (exLower.length > 10 && (normalized.includes(exLower) || normalizedCourse.includes(normalizedEx))) return true;
    
    // For shorter exception names, be more strict - only match if they are very similar
    if (exLower.length <= 10 && normalized.length > 5) {
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
        
        if (courseBase === exBase && courseLevel === exLevel) return true;
      } else {
        // Single word courses - use exact match only
        if (exLower.includes(normalized) || normalizedEx.includes(normalizedCourse)) return true;
      }
    }
    
    return false;
  });
  
  if (hasAPKeyword || isAPException) return "AP";

  // Check for Honors pattern
  const hasHonorsKeyword = /\bhonors?\b/.test(normalized);
  
  // Check Honors exceptions with Roman numeral normalization
  const isHonorsException = [...honorsExceptions].some(ex => {
    const exLower = ex.toLowerCase().trim();
    const normalizedCourse = normalizeNumbers(normalized);
    const normalizedEx = normalizeNumbers(exLower);
    
    // Exact match (direct or after normalization)
    if (normalized === exLower || normalizedCourse === normalizedEx) return true;
    
    // For longer exception names, check if course name contains the full exception
    if (exLower.length > 10 && (normalized.includes(exLower) || normalizedCourse.includes(normalizedEx))) return true;
    
    // For shorter exception names, be more strict - only match if they are very similar
    if (exLower.length <= 10 && normalized.length > 5) {
      // Split into words and check for meaningful overlap
      const courseWords = normalizedCourse.split(/\s+/);
      const exWords = normalizedEx.split(/\s+/);
      
      // For courses like "robotics i" vs "robotics 2", they need to match more precisely
      if (courseWords.length >= 2 && exWords.length >= 2) {
        // Both must have same base word and the level must match exactly
        const courseBase = courseWords[0];
        const courseLevel = courseWords[1];
        const exBase = exWords[0];
        const exLevel = exWords[1];
        
        if (courseBase === exBase && courseLevel === exLevel) return true;
      } else {
        // Single word courses - use exact match only
        if (exLower.includes(normalized) || normalizedEx.includes(normalizedCourse)) return true;
      }
    }
    
    return false;
  });

  if (hasHonorsKeyword || isHonorsException) return "Honors";

  return "Regular";
}function calculateGPAForGrades(grades: { grade: number; level: string }[]): GPAResult {
  if (grades.length === 0) return { unweighted: 0, weighted: 0 };

  let totalUnweighted = 0;
  let totalWeighted = 0;

  for (const { grade, level } of grades) {
    const base = Math.min(Math.max(grade, 0), 100);
    let weighted = base;

    if (level === "AP") weighted += 10;
    else if (level === "Honors") weighted += 5;

    totalUnweighted += base;
    totalWeighted += Math.min(weighted, 110);
  }

  // console.log(parseFloat((totalWeighted / grades.length).toFixed(2)));
  return {
    unweighted: parseFloat((totalUnweighted / grades.length).toFixed(2)),
    weighted: parseFloat((totalWeighted / grades.length).toFixed(2)),
  };
}

export function calculateTermGPAs(classes: SavedClass[]): Record<string, GPAResult> {
  const termLabels = ['sm1', 'sm2', 'rc1', 'rc2', 'rc3', 'rc4'] as const;

  const termGrades: Record<string, { grade: number; level: string }[]> = {};

  for (const term of termLabels) {
    termGrades[term] = [];
  }

  for (const c of classes) {
    // Skip classes without valid className
    if (!c || !c.className || typeof c.className !== 'string') {
      continue;
    }
    
    const level = getCourseLevel(c.className);
    for (const term of termLabels) {
      const grade = c[term];
      if (typeof grade === 'number' && grade >= 0) {
        termGrades[term].push({ grade, level });
      }
    }
  }

  const result: Record<string, GPAResult> = {};
  for (const term of termLabels) {
    result[term.toUpperCase()] = calculateGPAForGrades(termGrades[term]);
  }

  return result;
}