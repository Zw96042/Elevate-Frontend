import { UnifiedCourseData } from '@/lib/services';
import { Assignment } from '@/interfaces/interfaces';

/**
 * Transforms course data for showoff mode - sets all grades to 100/100
 * and GPA to perfect scores (100 unweighted, 104 weighted)
 */
export function transformDataForShowoffMode(coursesData: UnifiedCourseData[] | null): UnifiedCourseData[] | null {
  if (!coursesData) return null;

  return coursesData.map(course => ({
    ...course,
    // Transform assignments to all be 100/100
    assignments: course.assignments?.map(assignment => ({
      ...assignment,
      grade: '100',
      totalPoints: '100',
      earnedPoints: '100'
    })) || [],
    
    // Set semester grades to 100
    semester1Grade: 100,
    semester2Grade: 100,
    
    // Set all report card grades to 100
    reportCard1: 100,
    reportCard2: 100,
    reportCard3: 100,
    reportCard4: 100,
    
    // Set final grade to 100
    finalGrade: 100,
    
    // Transform historical grades to all be 100
    historicalGrades: {
      pr1: '100',
      pr2: '100', 
      rc1: '100',
      pr3: '100',
      pr4: '100',
      rc2: '100',
      pr5: '100',
      pr6: '100',
      rc3: '100',
      pr7: '100',
      pr8: '100',
      rc4: '100',
      sm1: '100',
      sm2: '100',
      finalGrade: '100'
    }
  }));
}

/**
 * Returns perfect GPA values for showoff mode
 */
export function getShowoffModeGPA() {
  return {
    unweighted: 100,
    weighted: 104
  };
}

/**
 * Returns varied GPA values for showoff mode graph
 */
export function getShowoffModeVariedGPA(index: number = 0) {
  // Create variation pattern: up-down-up-down with high scores
  const variationPattern = [98, 102, 96, 104, 99, 103, 97, 101, 100, 102, 98, 104, 100, 104];
  const unweightedScore = variationPattern[index] || 100;
  const weightedScore = Math.min(unweightedScore + 4, 104); // Add 4 for weighted, cap at 104
  
  return {
    unweighted: unweightedScore,
    weighted: weightedScore
  };
}

/**
 * Checks if showoff mode should be enabled based on username
 */
export function shouldEnableShowoffMode(username: string): boolean {
  return username === '96042';
}