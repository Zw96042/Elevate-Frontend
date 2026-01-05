// lib/unifiedGpaManager.tsx
// GPA calculation service using the new DataService
import { DataService, UnifiedCourseData } from './services';
import { calculateTermGPAs, getCourseLevel } from '@/utils/gpaCalculator';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { shouldEnableShowoffMode } from '@/utils/showoffMode';

export interface GPAData {
  unweighted: number;
  weighted: number;
}

export interface UnifiedGPAResult {
  success: boolean;
  gpaData?: Record<string, GPAData>;
  rawCourses?: UnifiedCourseData[];
  currentGradeLevel?: number;
  availableGradeLevels?: number[];
  error?: string;
  lastUpdated?: string;
}

type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

const getGradeNumber = (gradeLevel: GradeLevel): number | undefined => {
  switch (gradeLevel) {
    case 'Freshman': return 9;
    case 'Sophomore': return 10;
    case 'Junior': return 11;
    case 'Senior': return 12;
    case 'All Time': return undefined;
    default: return undefined;
  }
};

export class UnifiedGPAManager {
  /**
   * Get GPA data for a specific grade level
   */
  static async getGPAData(
    gradeLevel: GradeLevel = 'All Time', 
    forceRefresh: boolean = false
  ): Promise<UnifiedGPAResult> {
    try {
      console.log('📊 UnifiedGPAManager.getGPAData:', { gradeLevel, forceRefresh });
      
      // Use DataService instead of UnifiedDataManager
      const combinedResult = await DataService.getCombinedData(forceRefresh);
      
      if (!combinedResult.success) {
        const fallbackResult = await this.getFallbackGPAData(gradeLevel);
        if (fallbackResult.success) {
          return fallbackResult;
        }
        return {
          success: false,
          error: combinedResult.error || 'Failed to get combined data'
        };
      }
      
      const courses = combinedResult.courses || [];

      // Detect available grade levels
      const gradeLevelsSet = new Set<number>();
      courses.forEach((c: UnifiedCourseData) => {
        if (typeof c.gradeYear === 'number') {
          gradeLevelsSet.add(c.gradeYear);
        }
      });
      
      const availableGradeLevels = Array.from(gradeLevelsSet).sort((a, b) => a - b);
      let currentGradeLevel = availableGradeLevels.length > 0 
        ? availableGradeLevels[availableGradeLevels.length - 1] 
        : undefined;

      // Override with user selection
      const gradeNumber = getGradeNumber(gradeLevel);
      if (gradeNumber) {
        currentGradeLevel = gradeNumber;
      }

      // Filter courses for GPA calculation
      let filteredCourses = courses;
      if (currentGradeLevel) {
        filteredCourses = courses.filter((c: UnifiedCourseData) => c.gradeYear === currentGradeLevel);
      }

      const gpaData = this.calculateCurrentGradeGPA(filteredCourses);
      
      return {
        success: true,
        gpaData,
        rawCourses: courses,
        currentGradeLevel,
        availableGradeLevels,
        lastUpdated: combinedResult.lastUpdated
      };
    } catch (error: any) {
      console.error('❌ UnifiedGPAManager.getGPAData error:', error);
      
      const fallbackResult = await this.getFallbackGPAData(gradeLevel);
      if (fallbackResult.success) {
        return {
          ...fallbackResult,
          error: `Using manual grades: ${error.message}`
        };
      }
      
      return {
        success: false,
        error: error.message || 'Unknown error occurred'
      };
    }
  }

  /**
   * Calculate GPA for current grade level
   */
  static calculateCurrentGradeGPA(
    courses: UnifiedCourseData[], 
    showoffMode: boolean = false, 
    username: string = ''
  ): Record<string, GPAData> {
    try {
      // Showoff mode handling
      if (showoffMode && shouldEnableShowoffMode(username)) {
        return this.getShowoffModeGPA(courses);
      }

      const allTerms = ['PR1', 'PR2', 'RC1', 'PR3', 'PR4', 'RC2', 'PR5', 'PR6', 'RC3', 'PR7', 'PR8', 'RC4', 'SM1', 'SM2'];
      const termGPAs: Record<string, GPAData> = {};
      
      allTerms.forEach(term => {
        let totalUnweighted = 0;
        let totalBonus = 0;
        let courseCount = 0;
        
        courses.forEach(course => {
          let gradeStr = course.historicalGrades[term.toLowerCase() as keyof typeof course.historicalGrades];
          
          // RC rounding logic
          if (['RC1', 'RC2', 'RC3', 'RC4'].includes(term) && gradeStr && !isNaN(Number(gradeStr))) {
            gradeStr = Math.round(Number(gradeStr)).toString();
          }
          
          // Calculate semester averages if missing
          if (['SM1', 'SM2'].includes(term) && (!gradeStr || gradeStr === '')) {
            gradeStr = this.calculateSemesterAverage(course, term);
          }
          
          if (gradeStr && !isNaN(Number(gradeStr))) {
            const score = Number(gradeStr);
            totalUnweighted += score;
            
            const courseLevel = getCourseLevel(course.courseName);
            const bonus = courseLevel === "AP" ? 10 : courseLevel === "Honors" ? 5 : 0;
            totalBonus += bonus;
            courseCount++;
          }
        });
        
        if (courseCount > 0) {
          const avgUnweighted = totalUnweighted / courseCount;
          const avgWeighted = (totalUnweighted + totalBonus) / courseCount;
          termGPAs[term] = {
            unweighted: parseFloat(avgUnweighted.toFixed(2)),
            weighted: parseFloat(avgWeighted.toFixed(2))
          };
        }
      });
      
      return termGPAs;
    } catch (error) {
      console.warn('❌ Failed to calculate GPA:', error);
      return {};
    }
  }

  /**
   * Calculate semester average from quarter grades
   */
  private static calculateSemesterAverage(course: UnifiedCourseData, term: string): string | undefined {
    const { rc1, rc2, rc3, rc4, ex1, ex2 } = course.historicalGrades;
    
    if (term === 'SM1') {
      const roundedRC1 = rc1 && !isNaN(Number(rc1)) ? Math.round(Number(rc1)) : null;
      const roundedRC2 = rc2 && !isNaN(Number(rc2)) ? Math.round(Number(rc2)) : null;
      const examGrade = ex1 && !isNaN(Number(ex1)) ? Number(ex1) : null;
      
      if (roundedRC1 !== null && roundedRC2 !== null && examGrade !== null) {
        return (roundedRC1 * 0.4 + roundedRC2 * 0.4 + examGrade * 0.2).toString();
      } else if (roundedRC1 !== null && roundedRC2 !== null) {
        return ((roundedRC1 + roundedRC2) / 2).toString();
      } else if (roundedRC1 !== null) {
        return roundedRC1.toString();
      } else if (roundedRC2 !== null) {
        return roundedRC2.toString();
      }
    } else if (term === 'SM2') {
      const roundedRC3 = rc3 && !isNaN(Number(rc3)) ? Math.round(Number(rc3)) : null;
      const roundedRC4 = rc4 && !isNaN(Number(rc4)) ? Math.round(Number(rc4)) : null;
      const examGrade = ex2 && !isNaN(Number(ex2)) ? Number(ex2) : null;
      
      if (roundedRC3 !== null && roundedRC4 !== null && examGrade !== null) {
        return (roundedRC3 * 0.4 + roundedRC4 * 0.4 + examGrade * 0.2).toString();
      } else if (roundedRC3 !== null && roundedRC4 !== null) {
        return ((roundedRC3 + roundedRC4) / 2).toString();
      } else if (roundedRC3 !== null) {
        return roundedRC3.toString();
      } else if (roundedRC4 !== null) {
        return roundedRC4.toString();
      }
    }
    
    return undefined;
  }

  /**
   * Generate showoff mode GPA data
   */
  private static getShowoffModeGPA(courses: UnifiedCourseData[]): Record<string, GPAData> {
    const allTerms = ['PR1', 'PR2', 'RC1', 'PR3', 'PR4', 'RC2', 'PR5', 'PR6', 'RC3', 'PR7', 'PR8', 'RC4', 'SM1', 'SM2'];
    const termGPAs: Record<string, GPAData> = {};
    const variationPattern = [98, 104, 100, 98, 98, 104, 100, 98, 98, 104, 100];
    
    allTerms.forEach((term, index) => {
      const hasData = courses.some(course => {
        const gradeStr = course.historicalGrades[term.toLowerCase() as keyof typeof course.historicalGrades];
        return gradeStr !== undefined && gradeStr !== null && gradeStr !== '';
      });
      
      if (hasData) {
        const unweightedScore = variationPattern[index] || 100;
        termGPAs[term] = {
          unweighted: unweightedScore,
          weighted: Math.min(unweightedScore + 4, 104)
        };
      }
    });
    
    return termGPAs;
  }

  /**
   * Fallback to manually saved classes
   */
  private static async getFallbackGPAData(gradeLevel: GradeLevel): Promise<UnifiedGPAResult> {
    try {
      const key = `savedClasses-${gradeLevel}`;
      const data = await AsyncStorage.getItem(key);
      
      if (!data) {
        return {
          success: false,
          error: `No saved classes found for ${gradeLevel}`
        };
      }
      
      const savedClasses = JSON.parse(data);
      const gpaData = calculateTermGPAs(savedClasses);
      
      return {
        success: true,
        gpaData,
        rawCourses: savedClasses,
        currentGradeLevel: 10,
        availableGradeLevels: [9, 10, 11, 12],
        lastUpdated: new Date().toISOString()
      };
    } catch (error: any) {
      return {
        success: false,
        error: `Fallback failed: ${error.message}`
      };
    }
  }

  /**
   * Clear GPA cache
   */
  static async clearGPACache(): Promise<void> {
    try {
      await DataService.clearCache();
      
      const gradeLevels: GradeLevel[] = ['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time'];
      await Promise.all(
        gradeLevels.map(level => AsyncStorage.removeItem(`savedClasses-${level}`))
      );
      
      console.log('✅ GPA cache cleared');
    } catch (error) {
      console.error('❌ Error clearing GPA cache:', error);
    }
  }
}
