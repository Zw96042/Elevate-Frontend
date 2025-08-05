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

function calculateGPAForGrades(grades: { grade: number; level: string }[]): GPAResult {
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

export function calculatePeriodicGPA(classes: SavedClass[]): PeriodicGPA {
  const fallGrades = classes
    .filter(c => c.sm1 >= 0)
    .map(c => ({ grade: c.sm1, level: getCourseLevel(c.className) }));

  const springGrades = classes
    .filter(c => c.sm2 >= 0)
    .map(c => ({ grade: c.sm2, level: getCourseLevel(c.className) }));

  return {
    fall: calculateGPAForGrades(fallGrades),
    spring: calculateGPAForGrades(springGrades),
  };
}

export function calculateTermGPAs(classes: SavedClass[]): Record<string, GPAResult> {
  const termLabels = ['sm1', 'sm2', 'rc1', 'rc2', 'rc3', 'rc4'] as const;

  const termGrades: Record<string, { grade: number; level: string }[]> = {};

  for (const term of termLabels) {
    termGrades[term] = [];
  }

  for (const c of classes) {
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