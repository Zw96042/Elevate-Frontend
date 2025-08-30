// lib/unifiedDataManager.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { authenticate } from './authHandler';
import { fetchAcademicHistory } from './academicHistoryClient';
import { fetchSkywardReportCard } from './skywardClient';

const config = require('./development.config.js');

export interface UnifiedCourseData {
  courseId?: number;
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

  // Main method to get combined data
  public static async getCombinedData(forceRefresh: boolean = false): Promise<UnifiedDataResult> {
    try {
      console.log('🔄 UnifiedDataManager.getCombinedData called with forceRefresh:', forceRefresh);
      // Fetch the new combined scrape report (which includes academic history)
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

      // console.log("DATA: ", JSON.stringify(scrapeResult.data, null, 1));
      // Transform and return result
      return {
        success: true,
        courses: UnifiedDataManager.transformCombinedData(scrapeResult.data),
        lastUpdated: new Date().toISOString()
      };
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
  console.log('🟡 Backend response to transformCombinedData:', combined);
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
    console.log('🟢 Transformed courses:', courses);
    return courses;
  }
}
