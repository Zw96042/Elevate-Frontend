// lib/unifiedDataManager.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { authenticate } from './authHandler';
import { getCombinedAcademicHistoryReport, SkywardSessionCodes } from './skywardAcademicClient';

const config = require('./development.config.js');

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

// Cache keys and durations
const CACHE_KEY = 'unifiedCourseData';
const CACHE_TIMESTAMP_KEY = 'unifiedCourseDataTimestamp';
const ACADEMIC_HISTORY_CACHE_KEY = 'rawAcademicHistoryData';
const ACADEMIC_HISTORY_TIMESTAMP_KEY = 'rawAcademicHistoryTimestamp';
const GRADEBOOK_CACHE_KEY = 'rawGradebookData';
const GRADEBOOK_TIMESTAMP_KEY = 'rawGradebookTimestamp';

// Cache durations - Academic history changes less frequently than gradebook
const UNIFIED_CACHE_DURATION = 30 * 60 * 1000; // 30 minutes for combined data
const ACADEMIC_HISTORY_CACHE_DURATION = 6 * 60 * 60 * 1000; // 6 hours for academic history
const GRADEBOOK_CACHE_DURATION = 15 * 60 * 1000; // 15 minutes for gradebook data

export class UnifiedDataManager {
  private static currentYear: string | null = null;
  private static pendingRequest: Promise<UnifiedDataResult> | null = null;
  private static requestCounter = 0;

  // Clear all caches
  public static async clearCache(): Promise<void> {
    try {
      await AsyncStorage.multiRemove([
        CACHE_KEY,
        CACHE_TIMESTAMP_KEY,
        ACADEMIC_HISTORY_CACHE_KEY,
        ACADEMIC_HISTORY_TIMESTAMP_KEY,
        GRADEBOOK_CACHE_KEY,
        GRADEBOOK_TIMESTAMP_KEY
      ]);
      // Clear any pending requests since cache is cleared
      this.pendingRequest = null;
      console.log('🗑️ UnifiedDataManager cache cleared and pending requests reset');
    } catch (error) {
      console.error('❌ Failed to clear cache:', error);
    }
  }

  // Check if cache is valid
  private static async isCacheValid(timestampKey: string, cacheDuration: number = UNIFIED_CACHE_DURATION): Promise<boolean> {
    try {
      const timestampStr = await AsyncStorage.getItem(timestampKey);
      if (!timestampStr) return false;
      
      const timestamp = parseInt(timestampStr, 10);
      const now = Date.now();
      const isValid = (now - timestamp) < cacheDuration;
      
      console.log('📅 Cache validity check:', {
        timestampKey,
        age: Math.round((now - timestamp) / 1000),
        isValid,
        maxAge: cacheDuration / 1000
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
    const totalStartTime = Date.now();
    try {
      console.log(`� UnifiedDataManager: Starting getCombinedData (forceRefresh: ${forceRefresh})`);
      
      // Check cache first unless force refresh is requested
      if (!forceRefresh) {
        console.log('📋 UnifiedDataManager: Checking cache...');
        const cacheStartTime = Date.now();
        const cachedData = await this.getCachedData(CACHE_KEY, CACHE_TIMESTAMP_KEY);
        const cacheTime = Date.now() - cacheStartTime;
        
        if (cachedData) {
          console.log(`⚡ UnifiedDataManager: Using cached data (${cacheTime}ms) - ${cachedData.courses?.length || 0} courses`);
          // Ensure we always return success: true for valid cached data
          return {
            success: true,
            courses: cachedData.courses,
            lastUpdated: cachedData.lastUpdated
          };
        } else {
          console.log(`📊 UnifiedDataManager: No valid unified cache found (${cacheTime}ms)`);
        }
      } else {
        console.log('🔄 UnifiedDataManager: Force refresh requested, skipping all caches');
      }
      
      // CRITICAL: Use request deduplication for expired cache scenarios
      if (this.pendingRequest) {
        console.log('⏳ UnifiedDataManager: Request already in progress, waiting for existing...');
        const waitStartTime = Date.now();
        const result = await this.pendingRequest;
        const waitTime = Date.now() - waitStartTime;
        console.log(`⚡ UnifiedDataManager: Used deduplicated result (waited ${waitTime}ms)`);
        return result;
      }

      // Create the actual fetch promise and store it for deduplication
      this.pendingRequest = this.performOptimalFetch(forceRefresh, totalStartTime);
      
      try {
        const result = await this.pendingRequest;
        return result;
      } finally {
        // Clear pending request when done
        this.pendingRequest = null;
      }
    } catch (error: any) {
      this.pendingRequest = null; // Clear on error too
      const totalTime = Date.now() - totalStartTime;
      console.error(`💥 UnifiedDataManager: Error after ${totalTime}ms:`, error.message);
      return {
        success: false,
        error: error.message || 'Unknown error occurred'
      };
    }
  }

  // Perform the actual optimal fetch with parallel operations
  private static async performOptimalFetch(forceRefresh: boolean, totalStartTime: number): Promise<UnifiedDataResult> {
    try {
      // Try smart caching with separate component caches
      console.log('🧠 UnifiedDataManager: Trying smart separate caching...');
      const smartStartTime = Date.now();
      let scrapeResult = await this.fetchWithSmartCaching(forceRefresh);
      const smartTime = Date.now() - smartStartTime;
      console.log(`📡 UnifiedDataManager: Smart cache complete (${smartTime}ms) - Success: ${scrapeResult.success}`);
      
      // If session expired, try re-authenticating once
      if (
        !scrapeResult.success &&
        scrapeResult.error &&
        scrapeResult.error.toLowerCase().includes('session expired')
      ) {
        console.warn('🔄 UnifiedDataManager: Session expired detected, attempting re-authentication...');
        const reAuthStartTime = Date.now();
        const authResult = await authenticate();
        const reAuthTime = Date.now() - reAuthStartTime;
        
        if (authResult.success) {
          console.log(`✅ UnifiedDataManager: Re-authentication successful (${reAuthTime}ms), retrying fetch...`);
          const retryStartTime = Date.now();
          scrapeResult = await this.fetchScrapeReportData();
          const retryTime = Date.now() - retryStartTime;
          console.log(`🔄 UnifiedDataManager: Retry fetch complete (${retryTime}ms) - Success: ${scrapeResult.success}`);
        } else {
          console.error(`❌ UnifiedDataManager: Re-authentication failed (${reAuthTime}ms):`, authResult.error);
          return {
            success: false,
            error: 'Session expired and re-authentication failed: ' + (authResult.error || '')
          };
        }
      }
      
      if (!scrapeResult.success || !scrapeResult.data) {
        const error = scrapeResult.error || 'Failed to fetch combined academic data directly from Skyward';
        const totalTime = Date.now() - totalStartTime;
        console.error(`💥 UnifiedDataManager: Failed after ${totalTime}ms -`, error);
        return {
          success: false,
          error
        };
      }

      // Transform data
      console.log('🔄 UnifiedDataManager: Transforming raw data...');
      const transformStartTime = Date.now();
      const transformedCourses = UnifiedDataManager.transformCombinedData(scrapeResult.data);
      const transformTime = Date.now() - transformStartTime;
      console.log(`⚙️ UnifiedDataManager: Data transformation complete (${transformTime}ms) - ${transformedCourses.length} courses`);
      
      const result: UnifiedDataResult = {
        success: true,
        courses: transformedCourses,
        lastUpdated: new Date().toISOString()
      };

      // Cache the result - include success field for compatibility with DataService
      console.log('💾 UnifiedDataManager: Caching transformed data...');
      const cacheStartTime = Date.now();
      await this.setCachedData(CACHE_KEY, CACHE_TIMESTAMP_KEY, result);
      const cacheTime = Date.now() - cacheStartTime;
      
      const totalTime = Date.now() - totalStartTime;
      console.log(`🎉 UnifiedDataManager: Complete success! Cache saved (${cacheTime}ms) - Total time: ${totalTime}ms`);

      return result;
    } catch (error: any) {
      const totalTime = Date.now() - totalStartTime;
      console.error(`💥 UnifiedDataManager: Error after ${totalTime}ms:`, error.message);
      return {
        success: false,
        error: error.message || 'Unknown error occurred'
      };
    }
  }

  // Use parallel fetchScrapeReportData (smart caching can be added later)
  private static async fetchWithSmartCaching(forceRefresh: boolean = false): Promise<{ success: boolean; data?: any; error?: string }> {
    const smartStartTime = Date.now();
    try {
      console.log('🧠 fetchWithSmartCaching: Starting PARALLEL smart cache logic...');
      
      // Get session tokens once for potential API calls
      const [dwd, wfaacl, encses, userType, sessionid, baseUrl] = await Promise.all([
        AsyncStorage.getItem('dwd'),
        AsyncStorage.getItem('wfaacl'),
        AsyncStorage.getItem('encses'),
        AsyncStorage.getItem('User-Type'),
        AsyncStorage.getItem('sessionid'),
        AsyncStorage.getItem('skywardBaseURL')
      ]);

      const allSessionCodesExist = dwd && wfaacl && encses && userType && sessionid && baseUrl;
      if (!allSessionCodesExist) {
        console.log('❌ fetchWithSmartCaching: Missing session codes, falling back to full fetch...');
        return await this.fetchScrapeReportData();
      }

      const sessionCodes: SkywardSessionCodes = {
        dwd: dwd!,
        wfaacl: wfaacl!,
        encses: encses!,
        'User-Type': userType!,
        sessionid: sessionid!,
      };
      
      // Check what we need to fetch based on cache validity
      const [isAcademicCacheValid, isGradebookCacheValid] = await Promise.all([
        this.isCacheValid(ACADEMIC_HISTORY_TIMESTAMP_KEY, ACADEMIC_HISTORY_CACHE_DURATION),
        this.isCacheValid(GRADEBOOK_TIMESTAMP_KEY, GRADEBOOK_CACHE_DURATION)
      ]);
      
      const needAcademic = forceRefresh || !isAcademicCacheValid;
      const needGradebook = forceRefresh || !isGradebookCacheValid;
      
      
      
      // Execute parallel operations: fetch what we need, get what we can from cache
      const operations = [];
      
      if (needAcademic) {
        console.log('📚 fetchWithSmartCaching: Will fetch fresh academic history...');
        // TODO: Implement separate academic history caching
      } else {
        console.log('📚 fetchWithSmartCaching: Will use cached academic history...');
        operations.push(this.getCachedData(ACADEMIC_HISTORY_CACHE_KEY, ACADEMIC_HISTORY_TIMESTAMP_KEY));
      }
      
      if (needGradebook) {
        console.log('� fetchWithSmartCaching: Will fetch fresh gradebook...');
        // TODO: Implement separate gradebook caching
      } else {
        console.log('📊 fetchWithSmartCaching: Will use cached gradebook...');
        operations.push(this.getCachedData(GRADEBOOK_CACHE_KEY, GRADEBOOK_TIMESTAMP_KEY));
      }
      
      // Execute parallel operations
      const parallelStartTime = Date.now();
      const [academicHistory, gradebookData] = await Promise.all(operations);
      const parallelTime = Date.now() - parallelStartTime;
      
      console.log(`⚡ fetchWithSmartCaching: Parallel operations complete (${parallelTime}ms)`);
      

      
      // OPTIMIZATION: Always use the optimal parallel approach for maximum performance and simplicity
      console.log('🚀 fetchWithSmartCaching: Using OPTIMAL PARALLEL getCombinedAcademicHistoryReport...');
      const result = await getCombinedAcademicHistoryReport(baseUrl!, sessionCodes);
      
      // Ensure we return the correct format that UnifiedDataManager expects
      return { success: true, data: result };
      
    } catch (error: any) {
      console.error(`❌ fetchWithSmartCaching: Failed:`, error.message);
      return { success: false, error: error.message };
    }
  }

  // Note: Separate component caching can be implemented later by exporting 
  // individual functions from skywardAcademicClient

  // Fetch scrape report data using direct Skyward client
  private static async fetchScrapeReportData(): Promise<{ success: boolean; data?: any; error?: string }> {
    const fetchStartTime = Date.now();
    try {
      console.log('🔍 fetchScrapeReportData: Retrieving session tokens...');
      const tokenStartTime = Date.now();
      const [dwd, wfaacl, encses, userType, sessionid, baseUrl] = await Promise.all([
        AsyncStorage.getItem('dwd'),
        AsyncStorage.getItem('wfaacl'),
        AsyncStorage.getItem('encses'),
        AsyncStorage.getItem('User-Type'),
        AsyncStorage.getItem('sessionid'),
        AsyncStorage.getItem('skywardBaseURL')
      ]);
      const tokenTime = Date.now() - tokenStartTime;

      console.log(`📋 fetchScrapeReportData: Session tokens retrieved (${tokenTime}ms):`, { 
        hasDwd: !!dwd, hasWfaacl: !!wfaacl, hasEncses: !!encses, 
        hasUserType: !!userType, hasSessionid: !!sessionid, hasBaseUrl: !!baseUrl 
      });

      const allSessionCodesExist = dwd && wfaacl && encses && userType && sessionid && baseUrl;

      if (!allSessionCodesExist) {
        console.log('❌ fetchScrapeReportData: Missing session codes, calling authenticate...');
        const missingAuthStartTime = Date.now();
        const authResult = await authenticate();
        const missingAuthTime = Date.now() - missingAuthStartTime;
        
        if (!authResult.success) {
          console.log(`❌ fetchScrapeReportData: Authentication failed (${missingAuthTime}ms):`, authResult.error);
          return { success: false, error: authResult.error };
        }
        console.log(`✅ fetchScrapeReportData: Authentication successful (${missingAuthTime}ms), retrying...`);
        return await this.fetchScrapeReportData(); // Retry with new credentials
      }

      // Use the direct Skyward client instead of backend API
      console.log('🌐 fetchScrapeReportData: Making Skyward API call...');
      const skywardStartTime = Date.now();
      const sessionCodes: SkywardSessionCodes = {
        dwd: dwd!,
        wfaacl: wfaacl!,
        encses: encses!,
        'User-Type': userType!,
        sessionid: sessionid!,
      };

      const combinedData = await getCombinedAcademicHistoryReport(baseUrl!, sessionCodes);
      const skywardTime = Date.now() - skywardStartTime;
      const totalFetchTime = Date.now() - fetchStartTime;
      
      console.log(`✅ fetchScrapeReportData: Success! Skyward call (${skywardTime}ms), total (${totalFetchTime}ms)`);
      return { success: true, data: combinedData };
    } catch (error: any) {
      // Handle session expiry specifically
      if (error.code === 'SESSION_EXPIRED' || error.message.includes('Session expired')) {
        return { success: false, error: 'Session expired. Please re-authenticate.' };
      }
      return { success: false, error: error.message || 'Failed to fetch academic data directly from Skyward' };
    }
  }

  // Transform the backend combined data into frontend UnifiedCourseData[]
  public static transformCombinedData(combined: any): UnifiedCourseData[] {
    console.log('🔄 UnifiedDataManager.transformCombinedData called');
    console.log('📊 Combined data type:', typeof combined);
    console.log('📊 Combined data is array:', Array.isArray(combined));
    if (typeof combined === 'object' && !Array.isArray(combined)) {
      console.log('📊 Combined data keys:', Object.keys(combined));
    }
    
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
      console.log('📊 Processing flat array format, courses count:', combined.length);
      return combined.map((courseObj: any, index: number) => {
        console.log(`📊 Array course ${index}:`, {
          courseName: courseObj.courseName,
          courseId: courseObj.course || courseObj.courseId,
          corNumId: courseObj.corNumId,
          stuId: courseObj.stuId,
          section: courseObj.section,
          gbId: courseObj.gbId || courseObj.gbID
        });
        return {
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
        };
      });
    }

    // Handle nested object format (preferred)
    const courses: UnifiedCourseData[] = [];
    const yearKeys = Object.keys(combined).filter(k => k !== 'alt');
    console.log('📊 Processing nested object format, year keys:', yearKeys);
    if (yearKeys.length === 0) return courses;
    for (const yearKey of yearKeys) {
      const yearData = combined[yearKey];
      if (!yearData || !yearData.courses) continue;
      console.log(`📊 Processing year ${yearKey}, courses:`, Object.keys(yearData.courses));
      for (const [courseName, courseObjRaw] of Object.entries(yearData.courses)) {
        const courseObj = courseObjRaw as any;
        console.log(`📊 Nested course ${yearKey}/${courseName}:`, {
          courseId: courseObj.courseId,
          corNumId: courseObj.corNumId,
          stuId: courseObj.stuId,
          section: courseObj.section,
          gbId: courseObj.gbId || courseObj.gbID
        });
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
