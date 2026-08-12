// Data service - unified data fetching with caching
import AsyncStorage from '@react-native-async-storage/async-storage';
import { fetchCombinedAcademicData, fetchGradeInfo, getRequiredSessionData, handleAPIError } from '../api';
import { AuthService } from './auth-service';
import { RequestDeduplicator } from '../utils/request-deduplicator';
import { GradeInfoParams, GradeInfoResult } from '../types/api';
import { logger, Modules, log } from '../utils/logger';
import {
  getAccountDataGeneration,
  invalidateAccountDataCache,
  isAccountDataCurrent,
  writeAccountDataCache,
} from '../utils/account-data-cache';

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
    ex1?: string; ex2?: string;
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
    const generation = getAccountDataGeneration();
    const endTimer = logger.time(Modules.DATA, 'getCombinedData');
    
    try {
      // Check cache first
      if (!forceRefresh) {
        const cachedData = await this.getCachedData();
        if (cachedData && isAccountDataCurrent(generation)) {
          endTimer();
          log.cache.hit(Modules.DATA, 'unified_data');
          return cachedData;
        }
        log.cache.miss(Modules.DATA, 'unified_data');
      }

      // Use request deduplication
      const result = await RequestDeduplicator.deduplicate(`${UNIFIED_DATA_REQUEST_KEY}_${generation}`, async () => {
        return this.fetchAndCacheData(generation);
      });

      endTimer();
      if (!isAccountDataCurrent(generation)) {
        return { success: false, error: 'Account changed while loading courses' };
      }
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
    const generation = getAccountDataGeneration();
    if (retryCount > 1) {
      logger.warn(Modules.DATA, 'Max retry attempts reached for grade info');
      return { success: false, error: 'Max retry attempts reached' };
    }

    // Validate required parameters
    if (!params.stuId || !params.corNumId || !params.section || !params.gbId || !params.bucket) {
      logger.warn(Modules.DATA, 'Missing required parameters for grade info');
      return { success: false, error: 'Missing required parameters' };
    }

    const identity = [params.stuId, params.corNumId, params.section, params.gbId, params.bucket]
      .map(value => encodeURIComponent(value))
      .join('_');
    const cacheKey = `${GRADE_INFO_CACHE_PREFIX}${identity}`;
    const timestampKey = `${GRADE_INFO_TIMESTAMP_PREFIX}${identity}`;
    const requestKey = `${GRADE_INFO_REQUEST_PREFIX}${generation}_${identity}`;

    const endTimer = logger.time(Modules.DATA, `getGradeInfo:${params.bucket}`);

    try {
      // Check cache first
      const cachedData = await this.getGradeInfoCache(cacheKey, timestampKey);
      if (cachedData && isAccountDataCurrent(generation)) {
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
        if (!isAccountDataCurrent(generation)) {
          return { success: false, error: 'Account changed while loading grades' };
        }
        return this.getGradeInfo(params, retryCount + 1);
      }

      // Use request deduplication
      const result = await RequestDeduplicator.deduplicate(requestKey, async () => {
        try {
          const { sessionCodes, baseUrl } = await getRequiredSessionData();
          const gradeResult = await fetchGradeInfo(params, baseUrl, sessionCodes);
          if (!isAccountDataCurrent(generation)) {
            return { success: false, error: 'Account changed while loading grades' };
          }

          // Cache the result
          const cached = await this.setGradeInfoCache(cacheKey, timestampKey, gradeResult, generation);
          if (!cached) {
            return { success: false, error: 'Account changed while loading grades' };
          }

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
        if (!isAccountDataCurrent(generation)) {
          return { success: false, error: 'Account changed while loading grades' };
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
      const invalidation = invalidateAccountDataCache();
      RequestDeduplicator.clear();
      await invalidation;
      log.cache.clear(Modules.DATA, 'all');
    } catch (error) {
      logger.error(Modules.DATA, 'Failed to clear cache', error);
      throw error;
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
      logger.error(Modules.DATA, 'Failed to read cached grade info', error);
    }
    return null;
  }

  private static async setGradeInfoCache(
    cacheKey: string,
    timestampKey: string,
    data: GradeInfoResult,
    generation: number
  ): Promise<boolean> {
    try {
      const written = await writeAccountDataCache([
        [cacheKey, JSON.stringify(data)],
        [timestampKey, Date.now().toString()],
      ], generation);
      if (!written) return false;
      log.cache.set(Modules.DATA, cacheKey);
      return true;
    } catch (error) {
      logger.error(Modules.DATA, 'Failed to cache grade info', error);
      return false;
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
        const parsed = JSON.parse(cachedData);
        // Ensure success field exists for compatibility with UnifiedDataManager cache format
        if (!parsed.success && parsed.courses) {
          parsed.success = true;
        }
        return parsed;
      }
    } catch (error) {
      logger.error(Modules.DATA, 'Failed to read cached course data', error);
    }
    return null;
  }

  private static async setCachedData(
    data: UnifiedDataResult,
    generation: number
  ): Promise<boolean> {
    try {
      const written = await writeAccountDataCache([
        [CACHE_KEY, JSON.stringify(data)],
        [CACHE_TIMESTAMP_KEY, Date.now().toString()],
      ], generation);
      if (!written) return false;
      log.cache.set(Modules.DATA, 'unified_data');
      return true;
    } catch (error) {
      logger.error(Modules.DATA, 'Failed to cache data', error);
      return false;
    }
  }

  private static async fetchAndCacheData(generation: number): Promise<UnifiedDataResult> {
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
      if (!isAccountDataCurrent(generation)) {
        return { success: false, error: 'Account changed while loading courses' };
      }

      // Transform data
      const transformedCourses = this.transformCombinedData(combinedData);

      const result: UnifiedDataResult = {
        success: true,
        courses: transformedCourses,
        lastUpdated: new Date().toISOString(),
      };

      // Cache the result
      if (!(await this.setCachedData(result, generation))) {
        return { success: false, error: 'Account changed while loading courses' };
      }

      return result;
    } catch (error: any) {
      logger.error(Modules.DATA, 'fetchAndCacheData failed', error);

      if (!isAccountDataCurrent(generation)) {
        return { success: false, error: 'Account changed while loading courses' };
      }
      
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
          if (!isAccountDataCurrent(generation)) {
            return { success: false, error: 'Account changed while loading courses' };
          }
          const transformedCourses = this.transformCombinedData(combinedData);
          
          const result: UnifiedDataResult = {
            success: true,
            courses: transformedCourses,
            lastUpdated: new Date().toISOString(),
          };
          
          if (!(await this.setCachedData(result, generation))) {
            return { success: false, error: 'Account changed while loading courses' };
          }
          return result;
        } catch (retryError: any) {
          logger.error(Modules.DATA, 'Retry after re-authentication failed', retryError);
          return { success: false, error: retryError.message || 'Failed after re-authentication' };
        }
      }

      return {
        success: false,
        error: error.message || 'Failed to fetch academic data',
      };
    }
  }

  static transformCombinedData(combined: any): UnifiedCourseData[] {
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
        { key: 'ex1', label: 'EX1' },
        { key: 'rc3', label: 'Q3' },
        { key: 'rc4', label: 'Q4' },
        { key: 'sm2', label: 'S2' },
        { key: 'ex2', label: 'EX2' },
      ];
      return buckets.flatMap(bucket => {
        const value = courseObj[bucket.key];
        if (value === undefined || value === null || value === '') return [];
        const score = Number(value);
        return Number.isFinite(score) && Math.abs(score) <= 1_000_000_000
          ? [{ bucket: bucket.label, score }]
          : [];
      });
    }

    function gradeText(value: unknown): string | undefined {
      if (value === null || value === undefined) return undefined;
      const text = String(value).trim();
      if (!text) return undefined;
      const numeric = /^[+-]?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/i.test(text);
      if (numeric) {
        const score = Number(text);
        return Number.isFinite(score) && Math.abs(score) <= 1_000_000_000 ? text : undefined;
      }
      return /^(?:nan|[+-]?infinity)$/i.test(text) ? undefined : text;
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
          pr1: gradeText(courseObj.pr1), pr2: gradeText(courseObj.pr2), rc1: gradeText(courseObj.rc1),
          pr3: gradeText(courseObj.pr3), pr4: gradeText(courseObj.pr4), rc2: gradeText(courseObj.rc2),
          pr5: gradeText(courseObj.pr5), pr6: gradeText(courseObj.pr6), rc3: gradeText(courseObj.rc3),
          pr7: gradeText(courseObj.pr7), pr8: gradeText(courseObj.pr8), rc4: gradeText(courseObj.rc4),
          ex1: gradeText(courseObj.ex1), ex2: gradeText(courseObj.ex2),
          sm1: gradeText(courseObj.sm1), sm2: gradeText(courseObj.sm2),
          finalGrade: gradeText(courseObj.finalGrade),
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
            pr1: gradeText(courseObj.pr1), pr2: gradeText(courseObj.pr2), rc1: gradeText(courseObj.rc1),
            pr3: gradeText(courseObj.pr3), pr4: gradeText(courseObj.pr4), rc2: gradeText(courseObj.rc2),
            pr5: gradeText(courseObj.pr5), pr6: gradeText(courseObj.pr6), rc3: gradeText(courseObj.rc3),
            pr7: gradeText(courseObj.pr7), pr8: gradeText(courseObj.pr8), rc4: gradeText(courseObj.rc4),
            ex1: gradeText(courseObj.ex1), ex2: gradeText(courseObj.ex2),
            sm1: gradeText(courseObj.sm1), sm2: gradeText(courseObj.sm2),
            finalGrade: gradeText(courseObj.finalGrade),
          },
        });
      }
    }

    return courses;
  }
}
