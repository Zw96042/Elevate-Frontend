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
  "Multivariable Calculus", 
  "Linear Algebra",
  "Stats 2: Beyond AP Statistics",
  "Computer Science 2",
  "Computer Science 3",
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
  "Robotics 3",
  "Swift Coding",
  "Business Incubator",
  "Business ACCeleratoredu",
  "Anatomy and Physiology",
  "Engineering"
]);

function getCourseLevel(className: string): "AP" | "Honors" | "Regular" {
  const normalized = className.toLowerCase();

  const isAP = /\bap\b/.test(normalized) || [...apExceptions].some(ex => normalized.includes(ex.toLowerCase()));
  if (isAP) return "AP";

  const isHonors = /\bhonors?\b/.test(normalized) || [...honorsExceptions].some(ex => normalized.includes(ex.toLowerCase()));
  if (isHonors) return "Honors";

  return "Regular";
}

// Helper function to check if a grade is valid (not empty, not "P", not "X")
const isValidGrade = (grade: string): boolean => {
  return !!grade && grade !== "" && grade !== "P" && grade !== "X" && !isNaN(Number(grade));
};

// Calculate GPA for a specific term across all courses for a given grade level
const calculateTermGPA = (coursesData: Record<string, CourseData>, termKey: string, gradeLevel: number): GPAData => {
  let totalPoints = 0;
  let totalWeightedPoints = 0;
  let totalCourses = 0;

  Object.entries(coursesData).forEach(([courseKey, courseData]) => {
    const grade = courseData[termKey as keyof CourseData];
    // Extract the original class name (remove the year suffix)
    const className = courseKey.replace(/_\d{4}-\d{4}$/, '');
    
    if (isValidGrade(grade)) {
      const numericGrade = Number(grade);
      totalPoints += numericGrade;
      
      // Get the course level and add appropriate weight
      const courseLevel = getCourseLevel(className);
      let weightedGrade = numericGrade;
      
      if (courseLevel === "AP") {
        weightedGrade = numericGrade + 10;
      } else if (courseLevel === "Honors") {
        weightedGrade = numericGrade + 5;
      }
      
      totalWeightedPoints += Math.min(weightedGrade, 110);
      totalCourses++;
    }
  });

  if (totalCourses === 0) {
    return { unweighted: 0, weighted: 0 };
  }

  return {
    unweighted: parseFloat((totalPoints / totalCourses).toFixed(2)),
    weighted: parseFloat((totalWeightedPoints / totalCourses).toFixed(2))
  };
};

// Process academic history data and return GPA data for all terms
export const processAcademicHistory = (academicData: AcademicHistoryData): Record<string, GPAData> => {
  const gpaData: Record<string, GPAData> = {};
  
  // Filter to only include grades 9-12 and exclude alt
  const validYears = Object.entries(academicData).filter(([year, data]) => {
    return year !== 'alt' && data.grade >= 9 && data.grade <= 12;
  });

  // Combine all courses from all valid years
  const allCourses: Record<string, CourseData> = {};
  
  validYears.forEach(([year, yearData]) => {
    Object.entries(yearData.courses).forEach(([className, courseData]) => {
      // Skip courses with final grade of "P"
      if (courseData.finalGrade !== "P") {
        // Use a unique key that includes the year to avoid conflicts
        allCourses[`${className}_${year}`] = courseData;
      }
    });
  });

  // Calculate GPA for each term
  const terms = ['PR1', 'PR2', 'RC1', 'PR3', 'PR4', 'RC2', 'PR5', 'PR6', 'RC3', 'PR7', 'PR8', 'RC4', 'SM1', 'SM2'];
  
  terms.forEach(term => {
    gpaData[term] = calculateTermGPA(allCourses, term.toLowerCase(), 0);
  });

  return gpaData;
};

// Get current grade level from academic history
export const getCurrentGradeLevel = (academicData: AcademicHistoryData): number => {
  const validYears = Object.entries(academicData).filter(([year, data]) => {
    return year !== 'alt' && data.grade >= 9 && data.grade <= 12;
  });

  if (validYears.length === 0) return 9; // Default to freshman

  // Get the highest grade level
  return Math.max(...validYears.map(([, data]) => data.grade));
};
