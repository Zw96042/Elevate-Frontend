/**
 * Unified GPA Manager (Refactored)
 * Simplified GPA calculation using new data architecture
 */

import { UnifiedDataManager } from './unifiedDataManager';
import { UnifiedCourseData, UnifiedGPAResult, GradeLevel, GPAData } from '@/interfaces/interfaces';
import { CacheManager } from './core/CacheManager';
import { createComponentLogger } from './core/Logger';

const logger = createComponentLogger('UnifiedGPAManager');

export class UnifiedGPAManager {
  private static readonly GPA_CACHE_KEY = 'gpa_calculations';
  private static readonly CACHE_TTL = 15 * 60 * 1000; // 15 minutes

  /**
   * Get GPA data for a specific grade level
   */
  public static async getGPAData(
    gradeLevel: GradeLevel = 'All Time',
    forceRefresh: boolean = false
  ): Promise<UnifiedGPAResult> {
    try {
      console.log('📊 UnifiedGPAManager.getGPAData called with:', { gradeLevel, forceRefresh });

      const cacheKey = `${this.GPA_CACHE_KEY}_${gradeLevel}`;

      // Try cache first unless forcing refresh
      if (!forceRefresh) {
        const cachedGPA = await CacheManager.get<UnifiedGPAResult>(cacheKey);
        if (cachedGPA) {
          console.log('✅ Returning cached GPA data for', gradeLevel);
          return cachedGPA;
        }
      }

      // Get course data from UnifiedDataManager
      const dataResult = await UnifiedDataManager.getCombinedData(forceRefresh);
      
      if (!dataResult.success || !dataResult.courses) {
        return {
          success: false,
          error: dataResult.error || 'Failed to get course data'
        };
      }

      // Filter courses by grade level
      const filteredCourses = this.filterCoursesByGradeLevel(dataResult.courses, gradeLevel);
      
      // Calculate GPA
      const gpaData = this.calculateGPA(filteredCourses);
      
      // Get grade level info
      const gradeInfo = this.getGradeLevelInfo(dataResult.courses);

      const result: UnifiedGPAResult = {
        success: true,
        gpa: gpaData,
        rawCourses: filteredCourses,
        currentGradeLevel: gradeInfo.currentGradeLevel,
        availableGradeLevels: gradeInfo.availableGradeLevels,
        lastUpdated: new Date().toISOString()
      };

      // Cache the result
      await CacheManager.set(cacheKey, result, this.CACHE_TTL);

      console.log('✅ Successfully calculated GPA for', gradeLevel);
      return result;

    } catch (error: any) {
      logger.error('Error in getGPAData', error, {
        method: 'getGPAData',
        gradeLevel
      });
      
      return {
        success: false,
        error: 'Unable to calculate GPA. Please try again.'
      };
    }
  }

  /**
   * Filter courses by grade level
   */
  private static filterCoursesByGradeLevel(
    courses: UnifiedCourseData[], 
    gradeLevel: GradeLevel
  ): UnifiedCourseData[] {
    if (gradeLevel === 'All Time') {
      return courses;
    }

    const gradeNumber = this.getGradeNumber(gradeLevel);
    if (!gradeNumber) {
      return courses;
    }

    return courses.filter(course => course.gradeYear === gradeNumber);
  }

  /**
   * Calculate GPA from courses
   */
  private static calculateGPA(courses: UnifiedCourseData[]): GPAData {
    if (!courses || courses.length === 0) {
      return { gpa: 0, credits: 0 };
    }

    let totalPoints = 0;
    let totalCredits = 0;

    for (const course of courses) {
      const finalGrade = this.getFinalGrade(course);
      if (finalGrade && finalGrade !== 'N/A') {
        const gradePoints = this.convertGradeToPoints(finalGrade);
        const credits = 1; // Assume 1 credit per course for now
        
        totalPoints += gradePoints * credits;
        totalCredits += credits;
      }
    }

    const gpa = totalCredits > 0 ? totalPoints / totalCredits : 0;
    return {
      gpa: Math.round(gpa * 100) / 100, // Round to 2 decimal places
      credits: totalCredits,
      unweighted: Math.round(gpa * 100) / 100, // For compatibility with GpaCard
      weighted: Math.round(gpa * 100) / 100    // For compatibility with GpaCard
    };
  }

  /**
   * Get the final grade for a course
   */
  private static getFinalGrade(course: UnifiedCourseData): string | null {
    const grades = course.historicalGrades;
    
    // Priority order: final grade, then semester grades, then quarter grades
    if (grades.finalGrade && grades.finalGrade !== '') return grades.finalGrade;
    if (grades.sm2 && grades.sm2 !== '') return grades.sm2;
    if (grades.sm1 && grades.sm1 !== '') return grades.sm1;
    if (grades.rc4 && grades.rc4 !== '') return grades.rc4;
    if (grades.rc3 && grades.rc3 !== '') return grades.rc3;
    if (grades.rc2 && grades.rc2 !== '') return grades.rc2;
    if (grades.rc1 && grades.rc1 !== '') return grades.rc1;

    return null;
  }

  /**
   * Convert letter grade to GPA points
   */
  private static convertGradeToPoints(grade: string): number {
    // Remove any extra characters and get the letter grade
    const letterGrade = grade.trim().toUpperCase().charAt(0);
    
    switch (letterGrade) {
      case 'A': return 4.0;
      case 'B': return 3.0;
      case 'C': return 2.0;
      case 'D': return 1.0;
      case 'F': return 0.0;
      default: 
        // Try to parse as number (percentage)
        const numericGrade = parseFloat(grade);
        if (!isNaN(numericGrade)) {
          if (numericGrade >= 90) return 4.0;
          if (numericGrade >= 80) return 3.0;
          if (numericGrade >= 70) return 2.0;
          if (numericGrade >= 60) return 1.0;
          return 0.0;
        }
        return 0.0;
    }
  }

  /**
   * Get grade level information from courses
   */
  private static getGradeLevelInfo(courses: UnifiedCourseData[]): {
    currentGradeLevel?: number;
    availableGradeLevels: number[];
  } {
    const gradeLevels = new Set<number>();
    
    courses.forEach(course => {
      if (course.gradeYear && course.gradeYear > 0) {
        gradeLevels.add(course.gradeYear);
      }
    });

    const availableGradeLevels = Array.from(gradeLevels).sort();
    const currentGradeLevel = availableGradeLevels.length > 0 
      ? Math.max(...availableGradeLevels) 
      : undefined;

    return {
      currentGradeLevel,
      availableGradeLevels
    };
  }

  /**
   * Convert grade level string to number
   */
  private static getGradeNumber(gradeLevel: GradeLevel): number | undefined {
    switch (gradeLevel) {
      case 'Freshman': return 9;
      case 'Sophomore': return 10;
      case 'Junior': return 11;
      case 'Senior': return 12;
      case 'All Time': return undefined;
      default: return undefined;
    }
  }

  /**
   * Clear GPA cache
   */
  public static async clearCache(): Promise<void> {
    // Clear all GPA cache keys
    const gradeLevels: GradeLevel[] = ['All Time', 'Freshman', 'Sophomore', 'Junior', 'Senior'];
    
    for (const gradeLevel of gradeLevels) {
      const cacheKey = `${this.GPA_CACHE_KEY}_${gradeLevel}`;
      await CacheManager.delete(cacheKey);
    }
    
    console.log('🗑️ Cleared all GPA cache');
  }
}
