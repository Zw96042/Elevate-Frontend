/**
 * Unified Data Manager (Refactored)
 * Simplified data management using new ApiClient and CacheManager systems
 */

import { ApiClient } from './core/ApiClient';
import { CacheManager } from './core/CacheManager';
import { CredentialManager } from './core/CredentialManager';
import { createComponentLogger } from './core/Logger';
import { authenticate } from './authHandler';
import { UnifiedCourseData, UnifiedDataResult } from '@/interfaces/interfaces';

const logger = createComponentLogger('UnifiedDataManager');

export class UnifiedDataManager {
  private static readonly CACHE_KEY = 'unified_course_data';
  private static readonly CACHE_TTL = 30 * 60 * 1000; // 30 minutes
  
  // Authentication cooldown to prevent spam attempts
  private static lastAuthAttempt: number = 0;
  private static readonly AUTH_COOLDOWN = 10000; // 10 seconds between auth attempts

  /**
   * Main method to get combined course data
   */
  public static async getCombinedData(forceRefresh: boolean = false): Promise<UnifiedDataResult> {
    const timer = logger.startTimer('getCombinedData');
    
    try {
      logger.info('Starting unified data fetch', {
        method: 'getCombinedData',
        forceRefresh
      });

      // Try cache first unless forcing refresh
      if (!forceRefresh) {
        const cachedData = await CacheManager.get<UnifiedCourseData[]>(this.CACHE_KEY);
        if (cachedData) {
          logger.info('Returning cached course data', {
            method: 'getCombinedData',
            courseCount: cachedData.length
          });
          timer();
          return {
            success: true,
            courses: cachedData,
            lastUpdated: new Date().toISOString()
          };
        }
        logger.debug('No cached data found', {
          method: 'getCombinedData'
        });
      }

      // Ensure we have valid credentials
      logger.debug('Checking authentication status', {
        method: 'getCombinedData'
      });

      const hasValidSession = await CredentialManager.hasValidSession();
      if (!hasValidSession) {
        // Check authentication cooldown to prevent spam attempts
        const now = Date.now();
        const timeSinceLastAuth = now - this.lastAuthAttempt;
        
        if (timeSinceLastAuth < this.AUTH_COOLDOWN) {
          const remainingCooldown = Math.ceil((this.AUTH_COOLDOWN - timeSinceLastAuth) / 1000);
          logger.warn(`Authentication on cooldown, ${remainingCooldown}s remaining`, {
            method: 'getCombinedData',
            cooldownRemaining: remainingCooldown
          });
          timer();
          return {
            success: false,
            error: `Please wait ${remainingCooldown} seconds before trying again.`,
            requiresLogin: false
          };
        }
        
        logger.warn('No valid session found, attempting authentication', {
          method: 'getCombinedData'
        });

        this.lastAuthAttempt = now; // Set cooldown timestamp
        const authResult = await authenticate();
        if (!authResult.success) {
          logger.warn('Authentication failed, credentials may be invalid', {
            method: 'getCombinedData',
            authError: authResult.error
          });
          timer();
          
          // Check if this is a "need to login" error vs other auth errors
          const needsLogin = authResult.error?.includes('Please log in') || 
                            authResult.error?.includes('Missing or invalid credentials');
          
          return {
            success: false,
            error: needsLogin ? 
              'Please log in with your Skyward credentials to continue.' : 
              'Authentication failed. Please try again.',
            requiresLogin: needsLogin
          };
        }
        
        logger.info('Authentication successful', {
          method: 'getCombinedData'
        });
      }

      // Fetch fresh data from API
      logger.info('🚀 HEAVY LOGGING: Starting API fetch for report card', {
        method: 'getCombinedData',
        useCache: true,
        timestamp: new Date().toISOString()
      });

      const response = await ApiClient.fetchReportCard(true); // Use cache
      
      logger.info('📊 HEAVY LOGGING: API response received', {
        method: 'getCombinedData',
        success: response.success,
        hasData: !!response.data,
        errorMessage: response.error,
        dataType: typeof response.data,
        dataSize: response.data ? JSON.stringify(response.data).length : 0
      });
      
      if (!response.success || !response.data) {
        logger.error('💥 HEAVY LOGGING: Failed to fetch data from API', undefined, {
          method: 'getCombinedData',
          error: response.error,
          responseSuccess: response.success,
          hasData: !!response.data,
          fullResponse: JSON.stringify(response).substring(0, 500)
        });
        timer();
        return {
          success: false,
          error: response.error || 'Unable to load your course data. Please try again.'
        };
      }

      // Transform the data
      logger.debug('Transforming course data', {
        method: 'getCombinedData',
        dataSize: JSON.stringify(response.data).length
      });

      const transformedCourses = this.transformCourseData(response.data);

      // Cache the results
      await CacheManager.set(this.CACHE_KEY, transformedCourses, this.CACHE_TTL);

      logger.info('Successfully fetched and cached course data', {
        method: 'getCombinedData',
        courseCount: transformedCourses.length
      });
      
      timer();
      return {
        success: true,
        courses: transformedCourses,
        lastUpdated: new Date().toISOString()
      };

    } catch (error: any) {
      timer();
      logger.error('Unexpected error in getCombinedData', error, {
        method: 'getCombinedData'
      });
      
      return {
        success: false,
        error: 'An unexpected error occurred. Please try again.'
      };
    }
  }

  /**
   * Transform raw API data into UnifiedCourseData format
   */
  private static transformCourseData(rawData: any): UnifiedCourseData[] {
    if (!rawData) return [];

    // Handle different response formats
    let coursesArray: any[] = [];
    
    if (Array.isArray(rawData)) {
      coursesArray = rawData;
    } else if (rawData.courses && Array.isArray(rawData.courses)) {
      coursesArray = rawData.courses;
    } else if (rawData.combined && Array.isArray(rawData.combined)) {
      coursesArray = rawData.combined;
    } else if (rawData.combined && typeof rawData.combined === 'object') {
      // Handle the new format: { "combined": { "2024-2025": { "courses": [...], "grade": 9 }, ... } }
      logger.debug('Processing year-based combined data format', {
        method: 'transformCourseData',
        years: Object.keys(rawData.combined)
      });
      
      coursesArray = [];
      Object.entries(rawData.combined).forEach(([year, yearData]: [string, any]) => {
        if (yearData && yearData.courses && Array.isArray(yearData.courses)) {
          // Add grade year to each course if available
          const coursesWithGrade = yearData.courses.map((course: any) => ({
            ...course,
            gradeYear: course.gradeYear || yearData.grade
          }));
          coursesArray.push(...coursesWithGrade);
        }
      });
      
      logger.info('Extracted courses from year-based format', {
        method: 'transformCourseData',
        totalCourses: coursesArray.length,
        years: Object.keys(rawData.combined)
      });
    } else {
      logger.warn('Unexpected data format', {
        method: 'transformCourseData',
        dataStructure: typeof rawData,
        keys: Object.keys(rawData || {}),
        sample: rawData
      });
      return [];
    }

    return coursesArray
      .map(course => this.transformSingleCourse(course))
      .filter((course): course is UnifiedCourseData => course !== null);
  }

  /**
   * Transform a single course object
   */
  private static transformSingleCourse(courseObj: any): UnifiedCourseData | null {
    if (!courseObj || !courseObj.courseName) {
      return null;
    }

    return {
      courseId: courseObj.course || courseObj.courseId,
      stuId: courseObj.stuId || '',
      section: courseObj.section || '',
      gbId: courseObj.gbID || courseObj.gbId || '',
      courseName: courseObj.courseName,
      instructor: courseObj.instructor || null,
      period: courseObj.period || null,
      time: courseObj.time || null,
      semester: this.inferSemester(courseObj.terms || courseObj.termLength || ''),
      termLength: courseObj.terms || courseObj.termLength || '',
      gradeYear: courseObj.gradeYear || courseObj.grade || undefined,
      currentScores: this.buildCurrentScores(courseObj),
      historicalGrades: this.buildHistoricalGrades(courseObj)
    };
  }

  /**
   * Infer semester from term information
   */
  private static inferSemester(terms: string): 'fall' | 'spring' | 'both' | 'unknown' {
    if (!terms) return 'unknown';
    
    const normalizedTerms = terms.replace(/\s/g, '');
    
    switch (normalizedTerms) {
      case '1-4':
        return 'both';
      case '1-2':
        return 'fall';
      case '3-4':
        return 'spring';
      default:
        return 'unknown';
    }
  }

  /**
   * Build current scores array from course object
   */
  private static buildCurrentScores(courseObj: any): Array<{ bucket: string; score: number }> {
    const buckets = [
      { key: 'rc1', label: 'Q1' },
      { key: 'rc2', label: 'Q2' },
      { key: 'sm1', label: 'S1' },
      { key: 'rc3', label: 'Q3' },
      { key: 'rc4', label: 'Q4' },
      { key: 'sm2', label: 'S2' }
    ];

    return buckets
      .filter(bucket => {
        const value = courseObj[bucket.key];
        return value !== undefined && value !== null && value !== '' && !isNaN(Number(value));
      })
      .map(bucket => ({
        bucket: bucket.label,
        score: Number(courseObj[bucket.key])
      }));
  }

  /**
   * Build historical grades object from course object
   */
  private static buildHistoricalGrades(courseObj: any): UnifiedCourseData['historicalGrades'] {
    return {
      pr1: courseObj.pr1 || undefined,
      pr2: courseObj.pr2 || undefined,
      rc1: courseObj.rc1 || undefined,
      pr3: courseObj.pr3 || undefined,
      pr4: courseObj.pr4 || undefined,
      rc2: courseObj.rc2 || undefined,
      pr5: courseObj.pr5 || undefined,
      pr6: courseObj.pr6 || undefined,
      rc3: courseObj.rc3 || undefined,
      pr7: courseObj.pr7 || undefined,
      pr8: courseObj.pr8 || undefined,
      rc4: courseObj.rc4 || undefined,
      sm1: courseObj.sm1 || undefined,
      sm2: courseObj.sm2 || undefined,
      finalGrade: courseObj.finalGrade || undefined,
    };
  }

  /**
   * Clear all cached data
   */
  public static async clearCache(): Promise<void> {
    await CacheManager.delete(this.CACHE_KEY);
    console.log('🗑️ Cleared unified data cache');
  }

  /**
   * Get cache information
   */
  public static async getCacheInfo(): Promise<{
    hasCache: boolean;
    lastUpdated?: string;
  }> {
    const hasCache = await CacheManager.has(this.CACHE_KEY);
    return {
      hasCache,
      lastUpdated: hasCache ? new Date().toISOString() : undefined
    };
  }
}
