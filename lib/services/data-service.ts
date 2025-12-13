// Data service - unified data fetching with caching
import AsyncStorage from '@react-native-async-storage/async-storage';
import { fetchCombinedAcademicData, fetchGradeInfo, getRequiredSessionData, handleAPIError } from '../api';
import { AuthService } from './auth-service';
import { RequestDeduplicator } from '../utils/request-deduplicator';
import { GradeInfoParams, GradeInfoResult } from '../types/api';
import { logger, Modules, log } from '../utils/logger';

export interface UnifiedCourseData {
  courseId?: number;
  corNumId?: string;
  stuId?: string;
  section?: string;
  gbId?: string;
  courseName: string;
  instructor?: string | null;
  period?: number | null;
  time?: string | null;
  semester: 'fall' | 'spring' | 'both' | 'unknown';
  termLength: string;
  gradeYear?: number;
  currentScores: Array<{ bucket: string; score: number }>;
  historicalGrades: {
    pr1?: string; pr2?: string; rc1?: string;
    pr3?: string; pr4?: string; rc2?: string;
    pr5?: string; pr6?: string; rc3?: string;
    pr7?: string; pr8?: string; rc4?: string;
    sm1?: string; sm2?: string; finalGrade?: string;
  };
}

export interface UnifiedDataResult {
  success: boolean;
  courses?: UnifiedCourseData[];
  error?: string;
  lastUpdated?: string;
}

// Cache configuration
const CACHE_KEY = 'unifiedCourseData';
const CACHE_TIMESTAMP_KEY = 'unifiedCourseDataTimestamp';
const CACHE_DURATION = 30 * 60 * 1000; // 30 minutes

const GRADE_INFO_CACHE_PREFIX = 'gradeInfo_';
const GRADE_INFO_TIMESTAMP_PREFIX = 'gradeInfoTimestamp_';
const GRADE_INFO_CACHE_DURATION = 5 * 60 * 1000; // 5 minutes for grade info

const UNIFIED_DATA_REQUEST_KEY = 'unified_data';
const GRADE_INFO_REQUEST_PREFIX = 'grade_info_';

export class DataService {
  /**
   * Get combined academic data with caching
   */
  static async getCombinedData(forceRefresh = false): Promise<UnifiedDataResult> {
    const endTimer = logger.time(Modules.DATA, 'getCombinedData');
    
    try {
      // Check cache first
      if (!forceRefresh) {
        const cachedData = await this.getCachedData();
        if (cachedData) {
          endTimer();
          log.cache.hit(Modules.DATA, 'unified_data');
          return cachedData;
        }
        log.cache.miss(Modules.DATA, 'unified_data');
      }

      // Use request deduplication
      const result = await RequestDeduplicator.deduplicate(UNIFIED_DATA_REQUEST_KEY, async () => {
        return this.fetchAndCacheData();
      });
      
      endTimer();
      return result;
    } catch (error: any) {
      endTimer();
      logger.error(Modules.DATA, 'getCombinedData failed', error);
      return {
        success: false,
        error: error.message || 'Unknown error occurred',
      };
    }
  }

  /**
   * Fetch grade info for a specific course with caching
   */
  static async getGradeInfo(
    params: GradeInfoParams,
    retryCount = 0
  ): Promise<{ success: boolean; data?: GradeInfoResult; error?: string }> {
    if (retryCount > 1) {
      logger.warn(Modules.DATA, 'Max retry attempts reached for grade info');
      return { success: false, error: 'Max retry attempts reached' };
    }

    // Validate required parameters
    if (!params.stuId || !params.corNumId || !params.section || !params.gbId || !params.bucket) {
      logger.warn(Modules.DATA, 'Missing required parameters for grade info');
      return { success: false, error: 'Missing required parameters' };
    }

    const cacheKey = `${GRADE_INFO_CACHE_PREFIX}${params.corNumId}_${params.bucket}`;
    const timestampKey = `${GRADE_INFO_TIMESTAMP_PREFIX}${params.corNumId}_${params.bucket}`;
    const requestKey = `${GRADE_INFO_REQUEST_PREFIX}${params.corNumId}_${params.bucket}`;

    const endTimer = logger.time(Modules.DATA, `getGradeInfo:${params.bucket}`);

    try {
      // Check cache first
      const cachedData = await this.getGradeInfoCache(cacheKey, timestampKey);
      if (cachedData) {
        endTimer();
        log.cache.hit(Modules.DATA, `grade_${params.corNumId}_${params.bucket}`);
        return { success: true, data: cachedData };
      }
      
      log.cache.miss(Modules.DATA, `grade_${params.corNumId}_${params.bucket}`);

      // Check session
      const hasSession = await AuthService.hasValidSession();
      if (!hasSession) {
        const authResult = await AuthService.authenticate();
        if (!authResult.success) {
          return { success: false, error: authResult.error };
        }
        return this.getGradeInfo(params, retryCount + 1);
      }

      // Use request deduplication
      const result = await RequestDeduplicator.deduplicate(requestKey, async () => {
        try {
          const { sessionCodes, baseUrl } = await getRequiredSessionData();
          const gradeResult = await fetchGradeInfo(params, baseUrl, sessionCodes);

          // Cache the result
          await this.setGradeInfoCache(cacheKey, timestampKey, gradeResult);

          return {
            success: true,
            data: gradeResult,
          };
        } catch (error: any) {
          return handleAPIError(error, 'DataService.getGradeInfo');
        }
      });
      
      endTimer();
      
      if (result.success) {
        logger.success(Modules.DATA, `Grade info fetched: ${params.bucket}`);
      } else {
        logger.error(Modules.DATA, `Grade info fetch failed: ${params.bucket}`, result);
      }
      
      return result;
    } catch (error: any) {
      endTimer();
      
      // Handle session expiration
      if (error.code === 'SESSION_EXPIRED' && retryCount === 0) {
        logger.info(Modules.DATA, 'Session expired, re-authenticating');
        const authResult = await AuthService.authenticate();
        if (!authResult.success) {
          return { success: false, error: authResult.error };
        }
        return this.getGradeInfo(params, retryCount + 1);
      }

      logger.error(Modules.DATA, 'getGradeInfo error', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Clear all caches
   */
  static async clearCache(): Promise<void> {
    try {
      // Get all keys and remove grade info caches
      const allKeys = await AsyncStorage.getAllKeys();
      const gradeInfoKeys = allKeys.filter(
        key => key.startsWith(GRADE_INFO_CACHE_PREFIX) || key.startsWith(GRADE_INFO_TIMESTAMP_PREFIX)
      );
      
      await AsyncStorage.multiRemove([
        CACHE_KEY,
        CACHE_TIMESTAMP_KEY,
        ...gradeInfoKeys,
      ]);
      RequestDeduplicator.clear();
      log.cache.clear(Modules.DATA, 'all');
    } catch (error) {
      logger.error(Modules.DATA, 'Failed to clear cache', error);
    }
  }

  // Private methods

  private static async getGradeInfoCache(
    cacheKey: string,
    timestampKey: string
  ): Promise<GradeInfoResult | null> {
    try {
      const timestampStr = await AsyncStorage.getItem(timestampKey);
      if (!timestampStr) return null;

      const timestamp = parseInt(timestampStr, 10);
      const now = Date.now();

      if (now - timestamp >= GRADE_INFO_CACHE_DURATION) {
        return null;
      }

      const cachedData = await AsyncStorage.getItem(cacheKey);
      if (cachedData) {
        return JSON.parse(cachedData);
      }
    } catch (error) {
      console.error('❌ DataService: Failed to get cached grade info:', error);
    }
    return null;
  }

  private static async setGradeInfoCache(
    cacheKey: string,
    timestampKey: string,
    data: GradeInfoResult
  ): Promise<void> {
    try {
      await AsyncStorage.multiSet([
        [cacheKey, JSON.stringify(data)],
        [timestampKey, Date.now().toString()],
      ]);
      log.cache.set(Modules.DATA, cacheKey);
    } catch (error) {
      logger.error(Modules.DATA, 'Failed to cache grade info', error);
    }
  }

  private static async getCachedData(): Promise<UnifiedDataResult | null> {
    try {
      const timestampStr = await AsyncStorage.getItem(CACHE_TIMESTAMP_KEY);
      if (!timestampStr) {
        console.log('📅 DataService: No cache timestamp found');
        return null;
      }

      const timestamp = parseInt(timestampStr, 10);
      const now = Date.now();
      const age = now - timestamp;
      const ageMinutes = Math.round(age / (60 * 1000));

      console.log('📅 DataService: Cache check', {
        timestamp,
        now,
        age,
        ageMinutes,
        maxAgeMinutes: CACHE_DURATION / (60 * 1000),
        isExpired: age >= CACHE_DURATION
      });

      if (age >= CACHE_DURATION) {
        console.log('📅 DataService: Cache expired');
        return null;
      }

      const cachedData = await AsyncStorage.getItem(CACHE_KEY);
      if (cachedData) {
        console.log('✅ DataService: Using valid cached data');
        return JSON.parse(cachedData);
      }
    } catch (error) {
      console.error('❌ DataService: Failed to get cached data:', error);
    }
    return null;
  }

  private static async setCachedData(data: UnifiedDataResult): Promise<void> {
    try {
      await AsyncStorage.multiSet([
        [CACHE_KEY, JSON.stringify(data)],
        [CACHE_TIMESTAMP_KEY, Date.now().toString()],
      ]);
      log.cache.set(Modules.DATA, 'unified_data');
    } catch (error) {
      logger.error(Modules.DATA, 'Failed to cache data', error);
    }
  }

  private static async fetchAndCacheData(): Promise<UnifiedDataResult> {
    try {
      // Check session first and authenticate if needed
      const hasSession = await AuthService.hasValidSession();
      if (!hasSession) {
        console.log('🔐 DataService: No valid session, authenticating...');
        const authResult = await AuthService.authenticate();
        if (!authResult.success) {
          console.error('❌ DataService: Authentication failed:', authResult.error);
          return { success: false, error: authResult.error || 'Authentication failed' };
        }
        console.log('✅ DataService: Authentication successful');
      }

      const { sessionCodes, baseUrl } = await getRequiredSessionData();
      
      // Validate we have all required session data
      if (!sessionCodes || !baseUrl) {
        console.error('❌ DataService: Missing session credentials after authentication');
        return { success: false, error: 'Missing session credentials' };
      }

      const combinedData = await fetchCombinedAcademicData(baseUrl, sessionCodes);

      // Transform data
      const transformedCourses = this.transformCombinedData(combinedData);

      const result: UnifiedDataResult = {
        success: true,
        courses: transformedCourses,
        lastUpdated: new Date().toISOString(),
      };

      // Cache the result
      await this.setCachedData(result);

      return result;
    } catch (error: any) {
      console.error('❌ DataService: fetchAndCacheData error:', error);
      
      // Handle session expiration with retry limit
      if (error.code === 'SESSION_EXPIRED' || error.message?.includes('session')) {
        console.log('🔄 DataService: Session expired, attempting re-authentication...');
        const authResult = await AuthService.authenticate();
        if (!authResult.success) {
          return { success: false, error: `Session expired and re-authentication failed: ${authResult.error}` };
        }
        
        // Retry once after re-authentication
        try {
          const { sessionCodes, baseUrl } = await getRequiredSessionData();
          const combinedData = await fetchCombinedAcademicData(baseUrl, sessionCodes);
          const transformedCourses = this.transformCombinedData(combinedData);
          
          const result: UnifiedDataResult = {
            success: true,
            courses: transformedCourses,
            lastUpdated: new Date().toISOString(),
          };
          
          await this.setCachedData(result);
          return result;
        } catch (retryError: any) {
          console.error('❌ DataService: Retry after re-authentication failed:', retryError);
          return { success: false, error: retryError.message || 'Failed after re-authentication' };
        }
      }

      return {
        success: false,
        error: error.message || 'Failed to fetch academic data',
      };
    }
  }

  private static transformCombinedData(combined: any): UnifiedCourseData[] {
    function inferSemester(terms: string): 'fall' | 'spring' | 'both' | 'unknown' {
      if (!terms) return 'unknown';
      const t = terms.replace(/\s/g, '');
      if (t === '1-4') return 'both';
      if (t === '1-2') return 'fall';
      if (t === '3-4') return 'spring';
      return 'unknown';
    }

    function buildCurrentScores(courseObj: any): Array<{ bucket: string; score: number }> {
      const buckets = [
        { key: 'rc1', label: 'Q1' },
        { key: 'rc2', label: 'Q2' },
        { key: 'sm1', label: 'S1' },
        { key: 'rc3', label: 'Q3' },
        { key: 'rc4', label: 'Q4' },
        { key: 'sm2', label: 'S2' },
      ];
      return buckets
        .filter(b => courseObj[b.key] !== undefined && courseObj[b.key] !== null && courseObj[b.key] !== '')
        .map(b => ({ bucket: b.label, score: Number(courseObj[b.key]) }));
    }

    // Handle flat array format
    if (Array.isArray(combined)) {
      return combined.map((courseObj: any) => ({
        courseId: courseObj.course || courseObj.courseId,
        corNumId: courseObj.corNumId || "",
        stuId: courseObj.stuId || "",
        section: courseObj.section || "",
        gbId: courseObj.gbId || courseObj.gbID || "",
        courseName: courseObj.courseName,
        instructor: courseObj.instructor || null,
        period: courseObj.period || null,
        time: courseObj.time || null,
        semester: inferSemester(courseObj.terms || courseObj.termLength || ''),
        termLength: courseObj.terms || courseObj.termLength || '',
        gradeYear: courseObj.gradeYear || courseObj.grade || undefined,
        currentScores: buildCurrentScores(courseObj),
        historicalGrades: {
          pr1: courseObj.pr1, pr2: courseObj.pr2, rc1: courseObj.rc1,
          pr3: courseObj.pr3, pr4: courseObj.pr4, rc2: courseObj.rc2,
          pr5: courseObj.pr5, pr6: courseObj.pr6, rc3: courseObj.rc3,
          pr7: courseObj.pr7, pr8: courseObj.pr8, rc4: courseObj.rc4,
          sm1: courseObj.sm1, sm2: courseObj.sm2, finalGrade: courseObj.finalGrade,
        },
      }));
    }

    // Handle nested object format
    const courses: UnifiedCourseData[] = [];
    const yearKeys = Object.keys(combined).filter(k => k !== 'alt');
    
    for (const yearKey of yearKeys) {
      const yearData = combined[yearKey];
      if (!yearData || !yearData.courses) continue;

      for (const [courseName, courseObjRaw] of Object.entries(yearData.courses)) {
        const courseObj = courseObjRaw as any;
        courses.push({
          courseId: courseObj.courseId,
          corNumId: courseObj.corNumId || "",
          stuId: courseObj.stuId || "",
          section: courseObj.section || "",
          gbId: courseObj.gbId || courseObj.gbID || "",
          courseName,
          instructor: courseObj.instructor || null,
          period: courseObj.period || null,
          time: null,
          semester: inferSemester(courseObj.terms || ''),
          termLength: courseObj.terms || '',
          gradeYear: yearData.grade,
          currentScores: buildCurrentScores(courseObj),
          historicalGrades: {
            pr1: courseObj.pr1, pr2: courseObj.pr2, rc1: courseObj.rc1,
            pr3: courseObj.pr3, pr4: courseObj.pr4, rc2: courseObj.rc2,
            pr5: courseObj.pr5, pr6: courseObj.pr6, rc3: courseObj.rc3,
            pr7: courseObj.pr7, pr8: courseObj.pr8, rc4: courseObj.rc4,
            sm1: courseObj.sm1, sm2: courseObj.sm2, finalGrade: courseObj.finalGrade,
          },
        });
      }
    }

    return courses;
  }
}
