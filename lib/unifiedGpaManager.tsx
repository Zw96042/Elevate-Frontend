// lib/unifiedGpaManager.tsx
import { UnifiedDataManager, UnifiedCourseData } from './unifiedDataManager';
import { processAcademicHistory } from '@/utils/academicHistoryProcessor';
import { calculateTermGPAs, getCourseLevel } from '@/utils/gpaCalculator';
import AsyncStorage from '@react-native-async-storage/async-storage';


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

// Helper function to convert grade level names to numbers
const getGradeNumber = (gradeLevel: GradeLevel): number | undefined => {
  switch (gradeLevel) {
    case 'Freshman': return 9;
    case 'Sophomore': return 10;
    case 'Junior': return 11;
    case 'Senior': return 12;
    case 'All Time': return undefined; // All grades
    default: return undefined;
  }
};

export class UnifiedGPAManager extends UnifiedDataManager {

  // Get GPA data for current/all grade levels (historical grade support removed)
  public static async getGPAData(
    gradeLevel: GradeLevel = 'All Time', 
    forceRefresh: boolean = false
  ): Promise<UnifiedGPAResult> {
    try {
      console.log('📊 UnifiedGPAManager.getGPAData called with:', { gradeLevel, forceRefresh });
      // Get combined data from parent class
      const combinedResult = await this.getCombinedData(forceRefresh);
      console.log('📈 Combined data result:', { 
        success: combinedResult.success, 
        coursesCount: combinedResult.courses?.length || 0,
        error: combinedResult.error 
      });
      if (!combinedResult.success) {
        console.log('⚠️ Combined data failed, trying fallback...');
        // Try to fallback to manual classes if no unified data available
        const fallbackResult = await this.getFallbackGPAData(gradeLevel);
        if (fallbackResult.success) {
          console.log('✅ Fallback GPA data succeeded');
          return fallbackResult;
        }
        console.log('❌ Both unified and fallback failed');
        return {
          success: false,
          error: combinedResult.error || 'Failed to get combined data'
        };
      }
      const courses = combinedResult.courses || [];

      // Detect grade levels by parsing academic years from backend response
      let currentGradeLevel: number | undefined = undefined;
      const gradeLevelsSet = new Set<number>();
      courses.forEach((c: UnifiedCourseData) => {
        if (typeof c.gradeYear === 'number') {
          gradeLevelsSet.add(c.gradeYear);
        }
      });
      const availableGradeLevels = Array.from(gradeLevelsSet).sort((a, b) => a - b);
      if (availableGradeLevels.length > 0) {
        currentGradeLevel = availableGradeLevels[availableGradeLevels.length - 1];
      }
      // If user selected a grade, override currentGradeLevel
      const gradeNumber = getGradeNumber(gradeLevel);
      if (gradeNumber) {
        currentGradeLevel = gradeNumber;
      }
      // Filter courses ONLY for GPA calculation, not for rawCourses
      let filteredCourses = courses;
      if (currentGradeLevel) {
        filteredCourses = courses.filter((c: UnifiedCourseData) => c.gradeYear === currentGradeLevel);
      }
      console.log('🟢 Selected currentGradeLevel:', currentGradeLevel);
      console.log('🟢 Filtered courses for current grade:', filteredCourses);

      console.log('🔄 Processing courses for GPA calculation, count:', filteredCourses.length);
      // For current grade, use current scores with academicHistory term structure
      const gpaData = this.calculateCurrentGradeGPA(filteredCourses);
      console.log('📊 Current grade GPA calculation result:', {
        currentGradeLevel,
        availableGradeLevels
      });
      return {
        success: true,
        gpaData,
        rawCourses: courses, // always return all courses
        currentGradeLevel,
        availableGradeLevels,
        lastUpdated: combinedResult.lastUpdated
      };
    } catch (error: any) {
      console.error('❌ Error in UnifiedGPAManager.getGPAData:', error);
      console.error('❌ Error details:', { 
        message: error.message, 
        stack: error.stack,
        gradeLevel,
        forceRefresh 
      });
      // Try fallback to manual classes
      console.log('🔄 Attempting fallback to manual classes...');
      const fallbackResult = await this.getFallbackGPAData(gradeLevel);
      if (fallbackResult.success) {
        console.log('✅ Fallback successful, returning manual grade data');
        return {
          ...fallbackResult,
          error: `Using manual grades due to error: ${error.message}`
        };
      }
      console.log('❌ Fallback also failed');
      return {
        success: false,
        error: error.message || 'Unknown error occurred'
      };
    }
  }

  // Calculate GPA from unified data using existing academic history processor
  private static calculateGPAFromUnifiedData(academicData: any, gradeNumber?: number): Record<string, GPAData> {
    try {
      console.log('🧮 calculateGPAFromUnifiedData called with:', { 
        hasAcademicData: !!academicData, 
        gradeNumber,
        academicDataKeys: academicData ? Object.keys(academicData) : []
      });
      
      if (!academicData) {
        console.log('⚠️ No academic data provided to calculateGPAFromUnifiedData');
        return {};
      }
      
      const result = processAcademicHistory(academicData, gradeNumber);
      console.log('📊 processAcademicHistory result:', {
        termCount: Object.keys(result).length,
        terms: Object.keys(result),
        sampleTerm: Object.keys(result)[0] ? { 
          term: Object.keys(result)[0], 
          data: result[Object.keys(result)[0]] 
        } : null
      });
      
      return result;
    } catch (error) {
      console.warn('❌ Failed to process academic history for GPA:', error);
      return {};
    }
  }

  // Calculate GPA for current grade level using scrape report scores with academic history term structure
  public static calculateCurrentGradeGPA(courses: UnifiedCourseData[]): Record<string, GPAData> {
    try {
      // Calculate GPA for all terms using historicalGrades
      const allTerms = ['PR1', 'PR2', 'RC1', 'PR3', 'PR4', 'RC2', 'PR5', 'PR6', 'RC3', 'PR7', 'PR8', 'RC4', 'SM1', 'SM2'];
      const termGPAs: Record<string, GPAData> = {};
      allTerms.forEach(term => {
        let totalUnweighted = 0;
        let totalBonus = 0;
        let courseCount = 0;
        courses.forEach(course => {
          const gradeStr = course.historicalGrades[term.toLowerCase() as keyof typeof course.historicalGrades];
          if (gradeStr !== undefined && gradeStr !== null && gradeStr !== '' && !isNaN(Number(gradeStr))) {
            const score = Number(gradeStr);
            totalUnweighted += score;
            const courseLevel = getCourseLevel(course.courseName);
            let bonus = 0;
            if (courseLevel === "AP") {
              bonus = 10;
            } else if (courseLevel === "Honors") {
              bonus = 5;
            }
            totalBonus += bonus;
            courseCount++;
          }
        });
        if (courseCount > 0) {
          const avgUnweighted = totalUnweighted / courseCount;
          const weightedTotal = totalUnweighted + totalBonus;
          const avgWeighted = weightedTotal / courseCount;
          termGPAs[term] = {
            unweighted: parseFloat(avgUnweighted.toFixed(2)),
            weighted: parseFloat(avgWeighted.toFixed(2))
          };
        }
      });
      return termGPAs;
    } catch (error) {
      console.warn('❌ Failed to calculate current grade GPA:', error);
      return {};
    }
  }

  // Helper method to parse term length string into individual terms
  private static parseTermLength(termLength: string): string[] {
    const terms: string[] = [];
    
    switch (termLength) {
      case '1':
        terms.push('PR1', 'PR2', 'RC1');
        break;
      case '2':
        terms.push('PR3', 'PR4', 'RC2');
        break;
      case '1-2':
        terms.push('PR1', 'PR2', 'RC1', 'PR3', 'PR4', 'RC2');
        break;
      case '3':
        terms.push('PR5', 'PR6', 'RC3');
        break;
      case '4':
        terms.push('PR7', 'PR8', 'RC4');
        break;
      case '3-4':
        terms.push('PR5', 'PR6', 'RC3', 'PR7', 'PR8', 'RC4');
        break;
      case '1-4':
      case 'unknown':
      default:
        terms.push('PR1', 'PR2', 'RC1', 'PR3', 'PR4', 'RC2', 'PR5', 'PR6', 'RC3', 'PR7', 'PR8', 'RC4');
        break;
    }
    
    return terms;
  }

  // Helper method to get the appropriate score for a specific term
  private static getScoreForTerm(termGrades: Record<string, number>, term: string): number {
    // Map term names to score bucket names (corrected mapping based on actual sequence)
    // Sequence: TERM 1, TERM 2, TERM 3, TERM 4, TERM 5, TERM 6, SEM 1, TERM 7, TERM 8, TERM 9, TERM 10, TERM 11, TERM 12, SEM 2
    // Maps to:  PR1,    PR2,    RC1,    PR3,    PR4,    RC2,    SM1,   PR5,    PR6,    RC3,    PR7,    PR8,    RC4,    SM2
    const termToScoreMap: Record<string, string[]> = {
      // First semester terms
      'PR1': ['TERM 1'],
      'PR2': ['TERM 2'], 
      'RC1': ['TERM 3'],
      'PR3': ['TERM 4'],
      'PR4': ['TERM 5'],
      'RC2': ['TERM 6'],
      'SM1': ['SEM 1'],
      // Second semester terms
      'PR5': ['TERM 7'],
      'PR6': ['TERM 8'],
      'RC3': ['TERM 9'],
      'PR7': ['TERM 10'],
      'PR8': ['TERM 11'],
      'RC4': ['TERM 12'],
      'SM2': ['SEM 2']
    };
    
    const possibleScoreBuckets = termToScoreMap[term] || [];
    
    // Find the first available score for this term
    for (const bucket of possibleScoreBuckets) {
      if (termGrades[bucket] && termGrades[bucket] > 0) {
        return termGrades[bucket];
      }
    }
    
    return -1; // No score found
  }

  // Fallback method to get GPA data from manually saved classes
  private static async getFallbackGPAData(gradeLevel: GradeLevel): Promise<UnifiedGPAResult> {
    try {
      console.log('🔄 getFallbackGPAData called for:', gradeLevel);
      
      const key = `savedClasses-${gradeLevel}`;
      const data = await AsyncStorage.getItem(key);
      
      if (!data) {
        console.log('❌ No fallback data found for', gradeLevel);
        return {
          success: false,
          error: `No saved classes found for ${gradeLevel}`
        };
      }
      
      const savedClasses = JSON.parse(data);
      console.log('📝 Found saved classes:', savedClasses.length);
      
      // Process saved classes to calculate GPA
      const gpaData = calculateTermGPAs(savedClasses);
      
      return {
        success: true,
        gpaData,
        rawCourses: savedClasses,
        currentGradeLevel: 10, // Default
        availableGradeLevels: [9, 10, 11, 12],
        lastUpdated: new Date().toISOString()
      };
    } catch (error: any) {
      console.warn('❌ Fallback GPA data failed:', error);
      return {
        success: false,
        error: `Fallback failed: ${error.message}`
      };
    }
  }

  // Clear GPA cache (clears saved classes data used for fallback)
  public static async clearGPACache(): Promise<void> {
    try {
      console.log('🧹 Clearing GPA cache...');
      // Clear saved classes for all grade levels
      const gradeLevels: GradeLevel[] = ['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time'];
      const clearPromises = gradeLevels.map(gradeLevel => {
        const key = `savedClasses-${gradeLevel}`;
        console.log(`🗑️ Removing cache key: ${key}`);
        return AsyncStorage.removeItem(key);
      });

      await Promise.all(clearPromises);
      console.log('✅ GPA cache cleared successfully');
    } catch (error) {
      console.error('❌ Error clearing GPA cache:', error);
    }
  }
}
