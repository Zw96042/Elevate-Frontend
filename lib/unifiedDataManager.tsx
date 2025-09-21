// lib/unifiedDataManager.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { authenticate } from './authHandler';
import { fetchAcademicHistory } from './academicHistoryClient';
import { fetchSkywardReportCard } from './skywardClient';

const config = require('./development.config.js');

export interface UnifiedCourseData {
  courseId?: number;
  stuId?: string;
  section?: string;
  gbId?: string;
  courseName: string;
  instructor?: string | null;
  period?: number | null;
  time?: string | null;
  semester: 'fall' | 'spring' | 'both' | 'unknown';
  termLength: string; // From academic history: "1", "1-2", etc.
  gradeYear?: number; // Added for dynamic grade level detection
  // Current grades from scrape report
  currentScores: Array<{ bucket: string; score: number }>;
  // Historical data from academic history
  historicalGrades: {
    pr1?: string;
    pr2?: string;
    rc1?: string;
    pr3?: string;
    pr4?: string;
    rc2?: string;
    pr5?: string;
    pr6?: string;
    rc3?: string;
    pr7?: string;
    pr8?: string;
    rc4?: string;
    sm1?: string;
    sm2?: string;
    finalGrade?: string;
  };
}

export interface UnifiedDataResult {
  success: boolean;
  courses?: UnifiedCourseData[];
  error?: string;
  lastUpdated?: string;
}

// Cache keys
const CACHE_KEY = 'unifiedCourseData';
const CACHE_TIMESTAMP_KEY = 'unifiedCourseDataTimestamp';
const ACADEMIC_HISTORY_CACHE_KEY = 'rawAcademicHistoryData';
const ACADEMIC_HISTORY_TIMESTAMP_KEY = 'rawAcademicHistoryTimestamp';
const CACHE_DURATION = 30 * 60 * 1000; // 30 minutes

export class UnifiedDataManager {
  private static currentYear: string | null = null;

  // Clear all caches
  public static async clearCache(): Promise<void> {
    try {
      await AsyncStorage.multiRemove([
        CACHE_KEY,
        CACHE_TIMESTAMP_KEY,
        ACADEMIC_HISTORY_CACHE_KEY,
        ACADEMIC_HISTORY_TIMESTAMP_KEY
      ]);
      console.log('🗑️ UnifiedDataManager cache cleared');
    } catch (error) {
      console.error('❌ Failed to clear cache:', error);
    }
  }

  // Check if cache is valid
  private static async isCacheValid(timestampKey: string): Promise<boolean> {
    try {
      const timestampStr = await AsyncStorage.getItem(timestampKey);
      if (!timestampStr) return false;
      
      const timestamp = parseInt(timestampStr, 10);
      const now = Date.now();
      const isValid = (now - timestamp) < CACHE_DURATION;
      
      console.log('📅 Cache validity check:', {
        timestampKey,
        age: Math.round((now - timestamp) / 1000),
        isValid,
        maxAge: CACHE_DURATION / 1000
      });
      
      return isValid;
    } catch (error) {
      console.error('❌ Cache validity check failed:', error);
      return false;
    }
  }

  // Get cached data
  private static async getCachedData(dataKey: string, timestampKey: string): Promise<any | null> {
    try {
      const isValid = await this.isCacheValid(timestampKey);
      if (!isValid) return null;
      
      const cachedData = await AsyncStorage.getItem(dataKey);
      if (cachedData) {
        console.log('✅ Using cached data for:', dataKey);
        return JSON.parse(cachedData);
      }
    } catch (error) {
      console.error('❌ Failed to get cached data:', error);
    }
    return null;
  }

  // Set cached data
  private static async setCachedData(dataKey: string, timestampKey: string, data: any): Promise<void> {
    try {
      await AsyncStorage.multiSet([
        [dataKey, JSON.stringify(data)],
        [timestampKey, Date.now().toString()]
      ]);
      console.log('💾 Cached data saved for:', dataKey);
    } catch (error) {
      console.error('❌ Failed to cache data:', error);
    }
  }

  // Main method to get combined data
  public static async getCombinedData(forceRefresh: boolean = false): Promise<UnifiedDataResult> {
    try {
      console.log('🔄 UnifiedDataManager.getCombinedData called with forceRefresh:', forceRefresh);
      
      // Check cache first unless force refresh is requested
      if (!forceRefresh) {
        const cachedData = await this.getCachedData(CACHE_KEY, CACHE_TIMESTAMP_KEY);
        if (cachedData) {
          return {
            success: true,
            courses: cachedData.courses,
            lastUpdated: cachedData.lastUpdated
          };
        }
      }
      
      // Fetch fresh data from scrape report
      let scrapeResult = await this.fetchScrapeReportData();
      
      // If session expired, try re-authenticating once
      if (
        !scrapeResult.success &&
        scrapeResult.error &&
        scrapeResult.error.toLowerCase().includes('session expired')
      ) {
        console.warn('🔄 Session expired detected, attempting re-authentication...');
        const authResult = await authenticate();
        if (authResult.success) {
          scrapeResult = await this.fetchScrapeReportData();
        } else {
          return {
            success: false,
            error: 'Session expired and re-authentication failed: ' + (authResult.error || '')
          };
        }
      }
      
      if (!scrapeResult.success || !scrapeResult.data) {
        const error = scrapeResult.error || 'Failed to fetch combined scrape report data';
        console.error('💥', error);
        return {
          success: false,
          error
        };
      }

      // Transform data
      const transformedCourses = UnifiedDataManager.transformCombinedData(scrapeResult.data);
      const result = {
        success: true,
        courses: transformedCourses,
        lastUpdated: new Date().toISOString()
      };

      // Cache the result
      await this.setCachedData(CACHE_KEY, CACHE_TIMESTAMP_KEY, {
        courses: transformedCourses,
        lastUpdated: result.lastUpdated
      });

      return result;
    } catch (error: any) {
      return {
        success: false,
        error: error.message || 'Unknown error occurred'
      };
    }
  }

  // Fetch academic history data
  private static async fetchAcademicHistoryData(): Promise<{ success: boolean; data?: any; error?: string }> {
    try {
      const result = await fetchAcademicHistory();
      if (result.success && result.data) {
        return { success: true, data: result.data };
      } else {
        return { success: false, error: result.error || 'Failed to fetch academic history' };
      }
    } catch (error: any) {
      return { success: false, error: error.message || 'Academic history fetch error' };
    }
  }

  // Fetch scrape report data
  private static async fetchScrapeReportData(): Promise<{ success: boolean; data?: any; error?: string }> {
    try {
      const dwd = await AsyncStorage.getItem('dwd');
      const wfaacl = await AsyncStorage.getItem('wfaacl');
      const encses = await AsyncStorage.getItem('encses');
      const userType = await AsyncStorage.getItem('User-Type');
      const sessionid = await AsyncStorage.getItem('sessionid');
      const baseUrl = await AsyncStorage.getItem('baseUrl');

      const allSessionCodesExist = dwd && wfaacl && encses && userType && sessionid && baseUrl;

      if (!allSessionCodesExist) {
        const authResult = await authenticate();
        if (!authResult.success) {
          return { success: false, error: authResult.error };
        }
        return await this.fetchScrapeReportData(); // Retry with new credentials
      }

      const response = await fetchSkywardReportCard({ 
        dwd: dwd!, 
        wfaacl: wfaacl!, 
        encses: encses!, 
        userType: userType!, 
        sessionid: sessionid!, 
        baseUrl: baseUrl! 
      });
      if (response.success && response.combined) {
        return { success: true, data: response.combined };
      } else {
        return { success: false, error: 'Failed to fetch combined scrape report data' };
      }
    } catch (error: any) {
      return { success: false, error: error.message || 'Scrape report fetch error' };
    }
  }

  // Transform the backend combined data into frontend UnifiedCourseData[]
  public static transformCombinedData(combined: any): UnifiedCourseData[] {
    // Helper to infer semester from terms
    function inferSemester(terms: string): 'fall' | 'spring' | 'both' | 'unknown' {
      if (!terms) return 'unknown';
      const t = terms.replace(/\s/g, '');
      if (t === '1-4') return 'both';
      if (t === '1-2') return 'fall';
      if (t === '3-4') return 'spring';
      return 'unknown';
    }

    // Helper to build currentScores from available fields
    function buildCurrentScores(courseObj: any): Array<{ bucket: string; score: number }> {
      const buckets = [
        { key: 'rc1', label: 'Q1' },
        { key: 'rc2', label: 'Q2' },
        { key: 'sm1', label: 'S1' },
        { key: 'rc3', label: 'Q3' },
        { key: 'rc4', label: 'Q4' },
        { key: 'sm2', label: 'S2' }
      ];
      return buckets
        .filter(b => courseObj[b.key] !== undefined && courseObj[b.key] !== null && courseObj[b.key] !== '')
        .map(b => ({ bucket: b.label, score: Number(courseObj[b.key]) }));
    }

    // Handle flat array format (legacy or fallback)
    if (Array.isArray(combined)) {
      return combined.map((courseObj: any) => ({
        courseId: courseObj.course || courseObj.courseId,
        stuId: courseObj.stuId || "",
        section: courseObj.section || "",
        gbId: courseObj.gbID || "",
        courseName: courseObj.courseName,
        instructor: courseObj.instructor || null,
        period: courseObj.period || null,
        time: courseObj.time || null,
        semester: inferSemester(courseObj.terms || courseObj.termLength || ''),
        termLength: courseObj.terms || courseObj.termLength || '',
  gradeYear: courseObj.gradeYear || courseObj.grade || undefined,
        currentScores: buildCurrentScores(courseObj),
        historicalGrades: {
          pr1: courseObj.pr1,
          pr2: courseObj.pr2,
          rc1: courseObj.rc1,
          pr3: courseObj.pr3,
          pr4: courseObj.pr4,
          rc2: courseObj.rc2,
          pr5: courseObj.pr5,
          pr6: courseObj.pr6,
          rc3: courseObj.rc3,
          pr7: courseObj.pr7,
          pr8: courseObj.pr8,
          rc4: courseObj.rc4,
          sm1: courseObj.sm1,
          sm2: courseObj.sm2,
          finalGrade: courseObj.finalGrade,
        }
      }));
    }

    // Handle nested object format (preferred)
    const courses: UnifiedCourseData[] = [];
    const yearKeys = Object.keys(combined).filter(k => k !== 'alt');
    if (yearKeys.length === 0) return courses;
    for (const yearKey of yearKeys) {
      const yearData = combined[yearKey];
      if (!yearData || !yearData.courses) continue;
      for (const [courseName, courseObjRaw] of Object.entries(yearData.courses)) {
        const courseObj = courseObjRaw as any;
        courses.push({
          courseId: courseObj.courseId,
          stuId: courseObj.stuId || "",
          section: courseObj.section || "",
          gbId: courseObj.gbID || "",
          courseName,
          instructor: courseObj.instructor || null,
          period: courseObj.period || null,
          time: null,
          semester: inferSemester(courseObj.terms || ''),
          termLength: courseObj.terms || '',
          gradeYear: yearData.grade, // Assign grade from year object
          currentScores: buildCurrentScores(courseObj),
          historicalGrades: {
            pr1: courseObj.pr1,
            pr2: courseObj.pr2,
            rc1: courseObj.rc1,
            pr3: courseObj.pr3,
            pr4: courseObj.pr4,
            rc2: courseObj.rc2,
            pr5: courseObj.pr5,
            pr6: courseObj.pr6,
            rc3: courseObj.rc3,
            pr7: courseObj.pr7,
            pr8: courseObj.pr8,
            rc4: courseObj.rc4,
            sm1: courseObj.sm1,
            sm2: courseObj.sm2,
            finalGrade: courseObj.finalGrade,
          }
        });
      }
    }
    return courses;
  }
}
