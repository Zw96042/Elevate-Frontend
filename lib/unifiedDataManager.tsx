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
      
      // Check cache first (unless forcing refresh)
      if (!forceRefresh) {
        const cachedData = await this.getCachedData();
        if (cachedData.success) {
          console.log('✅ Using cached unified data, courses count:', cachedData.courses?.length || 0);
          return cachedData;
        }
        console.log('⚠️ Cache miss or expired:', cachedData.error);
      }

      console.log('🌐 Fetching fresh data from both APIs...');
      
      // Fetch both APIs in parallel
      const [academicResult, scrapeResult] = await Promise.allSettled([
        this.fetchAcademicHistoryData(),
        this.fetchScrapeReportData()
      ]);

      let academicData: any = null;
      let scrapeData: any[] = [];

      // Handle academic history result
      if (academicResult.status === 'fulfilled' && academicResult.value.success) {
        academicData = academicResult.value.data;
        console.log('✅ Academic history fetch succeeded, years found:', Object.keys(academicData || {}).length);
        console.log('📚 Academic data sample:', {
          keys: Object.keys(academicData || {}),
          currentYear: this.getCurrentAcademicYear(academicData),
          sampleYear: academicData ? Object.keys(academicData)[0] : null,
          sampleData: academicData && Object.keys(academicData)[0] ? academicData[Object.keys(academicData)[0]] : null
        });
        
        // Cache the raw academic history data for later use
        await this.cacheRawAcademicHistory(academicData);
        console.log('💾 Raw academic history cached');
      } else {
        console.warn('❌ Academic history fetch failed:', 
          academicResult.status === 'rejected' ? academicResult.reason : academicResult.value.error);
      }

      // Handle scrape report result
      if (scrapeResult.status === 'fulfilled' && scrapeResult.value.success) {
        scrapeData = scrapeResult.value.data || [];
        console.log('✅ Scrape report fetch succeeded, courses found:', scrapeData.length);
      } else {
        console.warn('❌ Scrape report fetch failed:', 
          scrapeResult.status === 'rejected' ? scrapeResult.reason : scrapeResult.value.error);
      }

      // If both failed, return error
      if (!academicData && scrapeData.length === 0) {
        const error = 'Failed to fetch data from both academic history and scrape report APIs';
        console.error('💥', error);
        return {
          success: false,
          error
        };
      }

      // Combine the data
      console.log('🔄 Combining data from both sources...');
      const combinedCourses = this.combineData(academicData, scrapeData);
      console.log('✅ Data combination complete, final courses count:', combinedCourses.length);

      // Cache the result
      const result: UnifiedDataResult = {
        success: true,
        courses: combinedCourses,
        lastUpdated: new Date().toISOString()
      };

      await this.cacheData(result);
      console.log('💾 Data cached successfully');
      
      return result;
    } catch (error: any) {
      console.error('Error in getCombinedData:', error);
      
      // Try to return cached data as fallback
      const cachedData = await this.getCachedData(true); // Ignore cache expiry
      if (cachedData.success) {
        return {
          ...cachedData,
          error: `Using cached data due to error: ${error.message}`
        };
      }
      
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
  private static async fetchScrapeReportData(): Promise<{ success: boolean; data?: any[]; error?: string }> {
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
      
      if (response.success && response.data) {
        return { success: true, data: response.data };
      } else {
        return { success: false, error: 'Failed to fetch scrape report data' };
      }
    } catch (error: any) {
      return { success: false, error: error.message || 'Scrape report fetch error' };
    }
  }

  // Combine academic history and scrape report data
  private static combineData(academicData: any, scrapeData: any[]): UnifiedCourseData[] {
    console.log('🔄 Starting data combination...');
    console.log('📚 Academic data available:', !!academicData);
    console.log('📊 Scrape data courses:', scrapeData.length);
    
    const combinedCourses: UnifiedCourseData[] = [];
    const currentYear = this.getCurrentAcademicYear(academicData);
    console.log('📅 Current academic year detected:', currentYear);

    // Get current year courses from academic history if available (ONLY for term length reference)
    let currentYearCourses: Record<string, any> = {};
    if (academicData && currentYear && academicData[currentYear]) {
      currentYearCourses = academicData[currentYear].courses || {};
      console.log('📖 Current year courses from academic history (for term length):', Object.keys(currentYearCourses).length);
    }

    // ONLY process scrape data courses (current/active courses)
    // Do NOT add academic-only courses to avoid showing previous year courses
    const processedScrapeNames = new Set<string>();
    console.log('🔄 Processing scrape data courses ONLY (no historical courses)...');
    
    scrapeData.forEach((scrapeInfo, index) => {
      if (!scrapeInfo.courseName || processedScrapeNames.has(scrapeInfo.courseName.toLowerCase())) {
        console.log(`⏭️ Skipping duplicate/invalid course at index ${index}:`, scrapeInfo.courseName || 'NO NAME');
        return; // Skip duplicates
      }
      processedScrapeNames.add(scrapeInfo.courseName.toLowerCase());
      
      console.log(`📝 Processing scrape course ${index + 1}/${scrapeData.length}: ${scrapeInfo.courseName}`);
      console.log(`   - Period: ${scrapeInfo.period}, Instructor: ${scrapeInfo.instructor}`);
      console.log(`   - Semester: ${scrapeInfo.semester}, Scores: ${scrapeInfo.scores?.length || 0}`);

      // Try to find matching academic history data ONLY for term length
      const originalName = scrapeInfo.courseName.toLowerCase();
      const cleanedName = originalName.replace(/[^\w\s]/g, '').trim();
      const spacesRemoved = originalName.replace(/\s+/g, '');
      
      let termLength = this.inferTermLengthFromSemester(scrapeInfo.semester || 'unknown');
      
      console.log(`   🔍 Looking for academic match for term length only:`, { originalName, cleanedName, spacesRemoved });
      console.log(`   📚 Available academic courses:`, Object.keys(currentYearCourses));
      
      // Try to find matching course for term length
      for (const [academicName, academicCourse] of Object.entries(currentYearCourses)) {
        const academicLower = academicName.toLowerCase();
        const academicCleaned = academicLower.replace(/[^\w\s]/g, '').trim();
        const academicSpacesRemoved = academicLower.replace(/\s+/g, '');
        
        console.log(`     🔍 Trying academic course: ${academicName}`);
        console.log(`     📊 Academic course term length:`, academicCourse.terms);
        
        if (academicLower === originalName || 
            academicCleaned === cleanedName ||
            academicSpacesRemoved === spacesRemoved ||
            academicLower.includes(cleanedName) ||
            cleanedName.includes(academicCleaned)) {
          termLength = academicCourse.terms || termLength;
          console.log(`   ✅ Academic match found for term length: ${academicName} -> ${termLength}`);
          break;
        }
      }
      
      console.log(`   📏 Final term length: ${termLength} (from ${termLength === this.inferTermLengthFromSemester(scrapeInfo.semester || 'unknown') ? 'semester inference' : 'academic history'})`);

      const combinedCourse: UnifiedCourseData = {
        courseId: scrapeInfo.course,
        courseName: scrapeInfo.courseName,
        instructor: scrapeInfo.instructor || null,
        period: scrapeInfo.period || null,
        time: scrapeInfo.time || null,
        semester: scrapeInfo.semester || 'unknown',
        termLength: termLength,
        currentScores: scrapeInfo.scores || [],
        
        // Leave historical grades empty since we're focusing on current data
        historicalGrades: {}
      };

      console.log(`   ➕ Created current course: ${combinedCourse.courseName} (term: ${combinedCourse.termLength}, period: ${combinedCourse.period})`);
      combinedCourses.push(combinedCourse);
    });

    console.log(`✅ Data combination complete. Current courses only: ${combinedCourses.length}`);
    console.log('📋 Final current courses summary:', combinedCourses.map(c => ({
      name: c.courseName,
      period: c.period,
      semester: c.semester,
      termLength: c.termLength,
      currentScores: c.currentScores.length
    })));
    
    return combinedCourses;
  }

  // Determine current academic year from academic data (renamed to avoid conflict)
  private static getCurrentAcademicYear(academicData: any): string | null {
    if (!academicData || typeof academicData !== 'object') {
      return null;
    }

    // Find the most recent year that's not 'alt' and has actual grade data
    const years = Object.keys(academicData)
      .filter(year => year !== 'alt' && /^\d{4}-\d{4}$/.test(year))
      .sort((a, b) => {
        const yearA = parseInt(a.split('-')[1]);
        const yearB = parseInt(b.split('-')[1]);
        return yearB - yearA; // Most recent first
      });

    console.log('📅 Available academic years:', years);

    // Look for a year that actually has grades (not all empty)
    for (const year of years) {
      const yearData = academicData[year];
      if (yearData && yearData.courses) {
        // Check if any course in this year has actual grades
        const hasGrades = Object.values(yearData.courses).some((course: any) => {
          return course.pr1 || course.pr2 || course.sm1 || course.sm2 || course.finalGrade ||
                 course.rc1 || course.rc2 || course.rc3 || course.rc4;
        });
        
        console.log(`📊 Year ${year}: ${Object.keys(yearData.courses).length} courses, hasGrades: ${hasGrades}`);
        
        if (hasGrades) {
          console.log(`✅ Selected year ${year} (has actual grades)`);
          return year;
        }
      }
    }

    console.log('⚠️ No year with grades found, using most recent:', years[0]);
    return years[0] || null;
  }

  // Get current grade level from academic data (static helper, not async)
  public static getCurrentGradeLevelFromData(academicData: any): number {
    const currentYear = this.getCurrentAcademicYear(academicData);
    if (!currentYear || !academicData[currentYear]) {
      return 10; // Default to sophomore (your current level)
    }
    
    return academicData[currentYear].grade || 10;
  }

  // Determine semester from term length string
  private static determineSemesterFromTerms(terms: string): 'fall' | 'spring' | 'both' | 'unknown' {
    if (!terms || terms === 'unknown') return 'unknown';

    // Parse terms like "1", "1-2", "3-4", "1-4", etc.
    const termMatch = terms.match(/(\d+)(?:-(\d+))?/);
    if (!termMatch) return 'unknown';

    const startTerm = parseInt(termMatch[1]);
    const endTerm = termMatch[2] ? parseInt(termMatch[2]) : startTerm;

    const hasEarlyTerms = startTerm <= 2 || endTerm <= 2;
    const hasLateTerms = startTerm >= 3 || endTerm >= 3;

    if (hasEarlyTerms && hasLateTerms) {
      return 'both';
    } else if (hasEarlyTerms) {
      return 'fall';
    } else if (hasLateTerms) {
      return 'spring';
    }

    return 'unknown';
  }

  // Infer term length from semester info (reverse mapping)
  private static inferTermLengthFromSemester(semester: string): string {
    switch (semester) {
      case 'fall':
        return '1-2';
      case 'spring':
        return '3-4';
      case 'both':
        return '1-4';
      default:
        return 'unknown';
    }
  }

  // Cache management
  private static async cacheData(data: UnifiedDataResult): Promise<void> {
    try {
      console.log('💾 Caching unified data...', { 
        coursesCount: data.courses?.length || 0, 
        timestamp: data.lastUpdated 
      });
      await AsyncStorage.setItem(CACHE_KEY, JSON.stringify(data));
      await AsyncStorage.setItem(CACHE_TIMESTAMP_KEY, Date.now().toString());
      console.log('✅ Cache write successful');
    } catch (error) {
      console.warn('❌ Failed to cache unified data:', error);
    }
  }

  private static async getCachedData(ignoreExpiry: boolean = false): Promise<UnifiedDataResult> {
    try {
      console.log('🔍 Attempting to retrieve cached data, ignoreExpiry:', ignoreExpiry);
      
      const cachedDataString = await AsyncStorage.getItem(CACHE_KEY);
      const timestampString = await AsyncStorage.getItem(CACHE_TIMESTAMP_KEY);

      console.log('📥 Cache retrieval results:', { 
        hasCachedData: !!cachedDataString, 
        hasTimestamp: !!timestampString,
        dataLength: cachedDataString?.length || 0
      });

      if (!cachedDataString || (!ignoreExpiry && !timestampString)) {
        console.log('❌ No cached data available');
        return { success: false, error: 'No cached data available' };
      }

      if (!ignoreExpiry) {
        const timestamp = parseInt(timestampString!);
        const now = Date.now();
        const age = now - timestamp;
        
        console.log('⏱️ Cache age check:', { 
          cacheAge: Math.round(age / 1000), 
          maxAge: Math.round(CACHE_DURATION / 1000), 
          expired: age > CACHE_DURATION 
        });
        
        if (age > CACHE_DURATION) {
          console.log('❌ Cached data expired');
          return { success: false, error: 'Cached data expired' };
        }
      }

      const cachedData = JSON.parse(cachedDataString);
      console.log('✅ Cache hit! Returning cached courses:', cachedData.courses?.length || 0);
      return { ...cachedData, success: true };
    } catch (error) {
      console.warn('❌ Failed to retrieve cached data:', error);
      return { success: false, error: 'Failed to parse cached data' };
    }
  }

  // Clear cache
  public static async clearCache(): Promise<void> {
    try {
      await AsyncStorage.multiRemove([CACHE_KEY, CACHE_TIMESTAMP_KEY, ACADEMIC_HISTORY_CACHE_KEY, ACADEMIC_HISTORY_TIMESTAMP_KEY]);
    } catch (error) {
      console.warn('Failed to clear unified data cache:', error);
    }
  }

  // Cache raw academic history data
  private static async cacheRawAcademicHistory(academicData: any): Promise<void> {
    try {
      console.log('💾 Caching raw academic history...', { 
        yearsCount: Object.keys(academicData || {}).length
      });
      await AsyncStorage.setItem(ACADEMIC_HISTORY_CACHE_KEY, JSON.stringify(academicData));
      await AsyncStorage.setItem(ACADEMIC_HISTORY_TIMESTAMP_KEY, Date.now().toString());
      console.log('✅ Raw academic history cache write successful');
    } catch (error) {
      console.warn('❌ Failed to cache raw academic history:', error);
    }
  }

  // Get cached raw academic history data
  private static async getCachedRawAcademicHistory(ignoreExpiry: boolean = false): Promise<{ success: boolean; data?: any; error?: string }> {
    try {
      console.log('🔍 Attempting to retrieve cached academic history, ignoreExpiry:', ignoreExpiry);
      
      const cachedDataString = await AsyncStorage.getItem(ACADEMIC_HISTORY_CACHE_KEY);
      const timestampString = await AsyncStorage.getItem(ACADEMIC_HISTORY_TIMESTAMP_KEY);

      console.log('📥 Academic history cache retrieval results:', { 
        hasCachedData: !!cachedDataString, 
        hasTimestamp: !!timestampString,
        dataLength: cachedDataString?.length || 0
      });

      if (!cachedDataString || (!ignoreExpiry && !timestampString)) {
        console.log('❌ No cached academic history available');
        return { success: false, error: 'No cached academic history available' };
      }

      if (!ignoreExpiry) {
        const timestamp = parseInt(timestampString!);
        const now = Date.now();
        const age = now - timestamp;
        
        console.log('⏱️ Academic history cache age check:', { 
          cacheAge: Math.round(age / 1000), 
          maxAge: Math.round(CACHE_DURATION / 1000), 
          expired: age > CACHE_DURATION 
        });
        
        if (age > CACHE_DURATION) {
          console.log('❌ Cached academic history expired');
          return { success: false, error: 'Cached academic history expired' };
        }
      }

      const cachedData = JSON.parse(cachedDataString);
      console.log('✅ Academic history cache hit! Years available:', Object.keys(cachedData || {}));
      return { success: true, data: cachedData };
    } catch (error) {
      console.warn('❌ Failed to retrieve cached academic history:', error);
      return { success: false, error: 'Failed to parse cached academic history' };
    }
  }

  // Get current grade level from stored academic data
  public static async getCurrentGradeLevel(): Promise<number> {
    try {
      const cachedData = await this.getCachedData(true); // Get cached data ignoring expiry
      if (cachedData.success && cachedData.courses) {
        // Try to determine from unified data
        const currentYear = new Date().getFullYear();
        const academicYear = currentYear >= 8 ? `${currentYear}-${currentYear + 1}` : `${currentYear - 1}-${currentYear}`;
        
        // For now, return 12 as default - this should be improved to actually detect current grade
        // TODO: Add proper grade level detection based on current academic year
        return 12;
      }
    } catch (error) {
      console.warn('Could not determine current grade level:', error);
    }
    return 12; // Default to Senior
  }

  // Convert unified course data back to academic history format for compatibility
  public static convertToAcademicHistoryFormat(courses: UnifiedCourseData[]): any {
    console.log('🔄 convertToAcademicHistoryFormat called with courses:', courses.length);
    
    const academicYears: any = {};
    const currentYear = '2024-2025'; // TODO: Make this dynamic based on current academic year

    // Group courses by their year (for now, assume all current courses are in current year)
    const currentYearCourses: any = {};

    courses.forEach((course, index) => {
      console.log(`   📚 Processing course ${index + 1}/${courses.length}: ${course.courseName}`);
      console.log(`      - termLength: ${course.termLength}`);
      console.log(`      - hasHistoricalGrades: ${Object.keys(course.historicalGrades).length > 0}`);
      console.log(`      - sample grades:`, {
        pr1: course.historicalGrades.pr1,
        pr2: course.historicalGrades.pr2,
        sm1: course.historicalGrades.sm1,
        sm2: course.historicalGrades.sm2,
        finalGrade: course.historicalGrades.finalGrade
      });
      
      const courseKey = course.courseName;
      
      const courseData = {
        terms: course.termLength,
        finalGrade: course.historicalGrades.finalGrade || '',
        sm1: course.historicalGrades.sm1 || '',
        sm2: course.historicalGrades.sm2 || '',
        pr1: course.historicalGrades.pr1 || '',
        pr2: course.historicalGrades.pr2 || '',
        pr3: course.historicalGrades.pr3 || '',
        pr4: course.historicalGrades.pr4 || '',
        pr5: course.historicalGrades.pr5 || '',
        pr6: course.historicalGrades.pr6 || '',
        pr7: course.historicalGrades.pr7 || '',
        pr8: course.historicalGrades.pr8 || '',
        rc1: course.historicalGrades.rc1 || '',
        rc2: course.historicalGrades.rc2 || '',
        rc3: course.historicalGrades.rc3 || '',
        rc4: course.historicalGrades.rc4 || '',
      };
      
      console.log(`      - converted data:`, courseData);
      currentYearCourses[courseKey] = courseData;
    });

    academicYears[currentYear] = {
      grade: 10, // Current grade level (sophomore)
      courses: currentYearCourses
    };

    console.log('✅ Academic history format created:', {
      year: currentYear,
      courseCount: Object.keys(currentYearCourses).length,
      courseNames: Object.keys(currentYearCourses)
    });

    return academicYears;
  }

  // Extract grade level information from academic data
  public static extractGradeLevelInfo(academicData: any): {
    currentGradeLevel: number;
    availableGradeLevels: number[];
  } {
    const gradeLevels = Object.entries(academicData)
      .filter(([year, data]: [string, any]) => year !== 'alt' && data.grade >= 9 && data.grade <= 12)
      .map(([_, data]: [string, any]) => data.grade)
      .sort((a: number, b: number) => a - b);

    return {
      currentGradeLevel: gradeLevels[gradeLevels.length - 1] || 10, // Default to sophomore (current)
      availableGradeLevels: gradeLevels
    };
  }

  // Get academic history data for a specific grade level
  public static async getAcademicHistoryForGrade(gradeLevel: number, forceRefresh: boolean = false): Promise<any> {
    try {
      console.log(`📚 getAcademicHistoryForGrade called for grade ${gradeLevel}, forceRefresh: ${forceRefresh}`);
      
      let academicData: any = null;
      
      // Try to get from cache first (unless forcing refresh)
      if (!forceRefresh) {
        const cachedResult = await this.getCachedRawAcademicHistory();
        if (cachedResult.success && cachedResult.data) {
          console.log('✅ Using cached raw academic history data');
          academicData = cachedResult.data;
        } else {
          console.log('⚠️ No cached academic history, fetching fresh:', cachedResult.error);
        }
      }
      
      // If no cached data or forcing refresh, fetch fresh data
      if (!academicData) {
        console.log('🌐 Fetching fresh academic history data...');
        const academicResult = await this.fetchAcademicHistoryData();
        
        if (!academicResult.success || !academicResult.data) {
          console.error('❌ Failed to fetch academic history:', academicResult.error);
          return null;
        }

        academicData = academicResult.data;
        
        // Cache the fresh data for future use
        await this.cacheRawAcademicHistory(academicData);
        console.log('💾 Fresh academic history cached');
      }

      console.log('📚 Available academic years:', Object.keys(academicData));

      // Find the year that corresponds to the requested grade level
      const yearForGrade = Object.entries(academicData).find(([year, data]: [string, any]) => {
        return year !== 'alt' && data.grade === gradeLevel;
      });

      if (!yearForGrade) {
        console.warn(`⚠️ No data found for grade level ${gradeLevel}`);
        console.log('📊 Available grades:', Object.entries(academicData)
          .filter(([year]) => year !== 'alt')
          .map(([year, data]: [string, any]) => ({ year, grade: data.grade }))
        );
        
        // For debugging: If looking for freshman year (grade 9), try to find data from 2022-2023
        if (gradeLevel === 9) {
          console.log('🔍 Looking specifically for 2022-2023 data for freshman year...');
          const freshmanYear = academicData['2022-2023'];
          if (freshmanYear) {
            console.log('✅ Found 2022-2023 data:', {
              grade: freshmanYear.grade,
              courseCount: Object.keys(freshmanYear.courses || {}).length,
              courseNames: Object.keys(freshmanYear.courses || {})
            });
            return {
              '2022-2023': freshmanYear
            };
          } else {
            console.log('❌ No 2022-2023 data found');
          }
        }
        
        return null;
      }

      const [yearKey, yearData] = yearForGrade;
      const typedYearData = yearData as any;
      console.log(`✅ Found grade ${gradeLevel} data in year ${yearKey}:`, {
        courseCount: Object.keys(typedYearData.courses || {}).length,
        courseNames: Object.keys(typedYearData.courses || {})
      });

      // Return in the expected academic history format
      return {
        [yearKey]: typedYearData
      };
      
    } catch (error: any) {
      console.error(`❌ Error getting academic history for grade ${gradeLevel}:`, error);
      return null;
    }
  }
}
