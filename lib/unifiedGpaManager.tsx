// lib/unifiedGpaManager.tsx
import { UnifiedDataManager, UnifiedCourseData } from './unifiedDataManager';
import { processAcademicHistory } from '@/utils/academicHistoryProcessor';
import { calculateTermGPAs } from '@/utils/gpaCalculator';
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

  // Get GPA data for a specific grade level
  public static async getGPAData(
    gradeLevel: GradeLevel = 'All Time', 
    forceRefresh: boolean = false
  ): Promise<UnifiedGPAResult> {
    try {
      console.log('📊 UnifiedGPAManager.getGPAData called with:', { gradeLevel, forceRefresh });
      
      const gradeNumber = getGradeNumber(gradeLevel);
      console.log('🎯 Target grade number:', gradeNumber);
      
      // For historical grade levels (not current Sophomore), fetch historical data directly
      if (gradeNumber && gradeNumber !== 10) {
        console.log(`📚 Fetching historical academic data specifically for grade level ${gradeNumber} (${gradeLevel})`);
        
        const historicalData = await UnifiedDataManager.getAcademicHistoryForGrade(gradeNumber, forceRefresh);
        console.log('📖 Historical data result:', {
          hasData: !!historicalData,
          dataKeys: historicalData ? Object.keys(historicalData) : []
        });
        
        if (!historicalData) {
          console.log('⚠️ No historical data found, trying fallback...');
          const fallbackResult = await this.getFallbackGPAData(gradeLevel);
          if (fallbackResult.success) {
            console.log('✅ Fallback GPA data succeeded for historical grade');
            return fallbackResult;
          }
          
          return {
            success: false,
            error: `No academic history found for grade level ${gradeLevel}`
          };
        }
        
        // Calculate GPA from historical data
        const gpaData = this.calculateGPAFromUnifiedData(historicalData, gradeNumber);
        console.log('📊 Historical GPA calculation result:', {
          hasGpaData: Object.keys(gpaData).length > 0,
          gpaKeys: Object.keys(gpaData)
        });
        
        // Get context for available grade levels
        const contextData = await UnifiedDataManager.getAcademicHistoryForGrade(10, false);
        const { currentGradeLevel: contextCurrentGrade, availableGradeLevels: contextAvailableGrades } = 
          contextData ? UnifiedDataManager.extractGradeLevelInfo(contextData) : 
          { currentGradeLevel: 10, availableGradeLevels: [9, 10, 11, 12] };

        return {
          success: true,
          gpaData,
          rawCourses: [], // No current courses for historical grades
          currentGradeLevel: contextCurrentGrade,
          availableGradeLevels: contextAvailableGrades,
          lastUpdated: new Date().toISOString()
        };
      }
      
      // For current grade level (Sophomore/10) or All Time, use the unified system
      console.log('📈 Using unified system for current/all grade levels');
      
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
      console.log('🔄 Processing courses for GPA calculation, count:', courses.length);
      
      // For current grade, use current scores with academicHistory term structure
      const gpaData = this.calculateCurrentGradeGPA(courses);
      
      // Extract available grade levels and current grade level from academic history
      const academicHistoryFormat = UnifiedDataManager.convertToAcademicHistoryFormat(courses);
      const { currentGradeLevel, availableGradeLevels } = UnifiedDataManager.extractGradeLevelInfo(academicHistoryFormat);
      
      console.log('📊 Current grade GPA calculation result:', {
        hasGpaData: Object.keys(gpaData).length > 0,
        gpaKeys: Object.keys(gpaData),
        currentGradeLevel,
        availableGradeLevels
      });

      return {
        success: true,
        gpaData,
        rawCourses: courses,
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
  private static calculateCurrentGradeGPA(courses: UnifiedCourseData[]): Record<string, GPAData> {
    try {
      console.log('📊 calculateCurrentGradeGPA called with courses:', courses.length);
      
      // Create a synthetic academic history structure with real current scores
      const syntheticAcademicData: any = {};
      const currentYear = '2024-2025';
      
      // Group courses by term structure
      const termCourses: Record<string, any[]> = {};
      
      courses.forEach((course, index) => {
        const termLength = course.termLength || '1-4';
        
        // Convert current scores to term-based grades
        const termGrades: Record<string, number> = {};
        course.currentScores.forEach(score => {
          termGrades[score.bucket] = score.score;
        });
        
        // Create course entry for each relevant term based on termLength
        const courseEntry = {
          courseName: course.courseName,
          termGrades,
          termLength
        };
        
        // Determine which terms this course spans
        const terms = this.parseTermLength(termLength);
        terms.forEach(term => {
          if (!termCourses[term]) {
            termCourses[term] = [];
          }
          termCourses[term].push(courseEntry);
        });
      });
      
      console.log('📋 Term courses mapping:', Object.keys(termCourses).map(term => ({
        term,
        courseCount: termCourses[term].length
      })));
      
      // Calculate GPA for each term
      const termGPAs: Record<string, GPAData> = {};
      
      Object.entries(termCourses).forEach(([term, termCourseList]) => {
        const scores: number[] = [];
        termCourseList.forEach(courseEntry => {
          // Get the score for this specific term
          const termScore = this.getScoreForTerm(courseEntry.termGrades, term);
          if (termScore > 0) {
            scores.push(termScore);
          }
        });
        
        if (scores.length > 0) {
          const avgScore = scores.reduce((sum, score) => sum + score, 0) / scores.length;
          const gpaData = this.convertScoreToGPA(avgScore);
          termGPAs[term] = gpaData;
        }
      });
      
      console.log('✅ Current grade GPA calculation complete:', {
        termsCalculated: Object.keys(termGPAs).length,
        terms: Object.keys(termGPAs)
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

  // Helper method to convert percentage score to GPA
  private static convertScoreToGPA(score: number): GPAData {
    // Standard 4.0 scale conversion
    let unweighted = 0;
    let weighted = 0; // Assuming regular classes, would need course level info for true weighted
    
    if (score >= 97) {
      unweighted = weighted = 4.0;
    } else if (score >= 93) {
      unweighted = weighted = 3.7;
    } else if (score >= 90) {
      unweighted = weighted = 3.3;
    } else if (score >= 87) {
      unweighted = weighted = 3.0;
    } else if (score >= 83) {
      unweighted = weighted = 2.7;
    } else if (score >= 80) {
      unweighted = weighted = 2.3;
    } else if (score >= 77) {
      unweighted = weighted = 2.0;
    } else if (score >= 73) {
      unweighted = weighted = 1.7;
    } else if (score >= 70) {
      unweighted = weighted = 1.3;
    } else if (score >= 67) {
      unweighted = weighted = 1.0;
    } else if (score >= 65) {
      unweighted = weighted = 0.7;
    }
    
    // Convert to 100-point scale for display
    const scaledUnweighted = (unweighted / 4.0) * 100;
    const scaledWeighted = (weighted / 4.0) * 100;
    
    return {
      unweighted: scaledUnweighted,
      weighted: scaledWeighted
    };
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

  // Clear GPA cache (delegates to parent class)
  public static async clearGPACache(): Promise<void> {
    return this.clearCache();
  }
}
