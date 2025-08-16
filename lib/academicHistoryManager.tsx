// lib/academicHistoryManager.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { fetchAcademicHistory } from './academicHistoryClient';
import { processAcademicHistory, getCurrentGradeLevel } from '@/utils/academicHistoryProcessor';

interface CachedAcademicData {
  data: any;
  timestamp: number;
  academicYear: string;
}

interface GPAData {
  unweighted: number;
  weighted: number;
}

export class AcademicHistoryManager {
  private static CACHE_KEY = 'academicHistoryCache';
  private static CACHE_DURATION = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
  private static activeRequest: Promise<any> | null = null; // Prevent concurrent requests

  // Get current academic year (e.g., "2024-2025")
  private static getCurrentAcademicYear(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth();
    
    // Academic year typically starts in August/September
    if (month >= 7) { // August or later
      return `${year}-${year + 1}`;
    } else { // Before August
      return `${year - 1}-${year}`;
    }
  }

  // Get available grade levels from academic data
  private static getAvailableGradeLevels(academicData: any): number[] {
    const gradeLevels = new Set<number>();
    
    Object.entries(academicData).forEach(([year, yearData]: [string, any]) => {
      if (year !== 'alt' && yearData.grade >= 9 && yearData.grade <= 12) {
        gradeLevels.add(yearData.grade);
      }
    });
    
    return Array.from(gradeLevels).sort();
  }

  // Check if we have valid cached data for the current academic year
  private static async hasValidCache(): Promise<boolean> {
    try {
      const cached = await AsyncStorage.getItem(this.CACHE_KEY);
      if (!cached) return false;

      const cachedData: CachedAcademicData = JSON.parse(cached);
      const currentAcademicYear = this.getCurrentAcademicYear();
      const now = Date.now();

      // Cache is valid if it's for the current academic year and not expired
      return cachedData.academicYear === currentAcademicYear && 
             (now - cachedData.timestamp) < this.CACHE_DURATION;
    } catch (error) {
      console.error('Error checking cache validity:', error);
      return false;
    }
  }

  // Get cached data
  private static async getCachedData(): Promise<any | null> {
    try {
      const cached = await AsyncStorage.getItem(this.CACHE_KEY);
      if (!cached) return null;

      const cachedData: CachedAcademicData = JSON.parse(cached);
      return cachedData.data;
    } catch (error) {
      console.error('Error getting cached data:', error);
      return null;
    }
  }

  // Cache data for current academic year
  private static async cacheData(data: any): Promise<void> {
    try {
      const cacheData: CachedAcademicData = {
        data,
        timestamp: Date.now(),
        academicYear: this.getCurrentAcademicYear()
      };

      await AsyncStorage.setItem(this.CACHE_KEY, JSON.stringify(cacheData));
    } catch (error) {
      console.error('Error caching data:', error);
    }
  }

  // Get academic history with smart caching
  public static async getAcademicHistory(forceRefresh: boolean = false, gradeLevel?: number): Promise<{
    success: boolean;
    gpaData?: Record<string, GPAData>;
    rawData?: any;
    currentGradeLevel?: number;
    availableGradeLevels?: number[];
    error?: string;
    fromCache?: boolean;
  }> {
    // If there's already an active request and we're not forcing refresh, wait for it
    if (!forceRefresh && this.activeRequest) {
      return await this.activeRequest;
    }

    // Create the request promise
    const requestPromise = this.executeRequest(forceRefresh, gradeLevel);
    
    // Store it as the active request
    this.activeRequest = requestPromise;
    
    try {
      const result = await requestPromise;
      return result;
    } finally {
      // Clear the active request when done
      this.activeRequest = null;
    }
  }

  private static async executeRequest(forceRefresh: boolean, gradeLevel?: number): Promise<{
    success: boolean;
    gpaData?: Record<string, GPAData>;
    rawData?: any;
    currentGradeLevel?: number;
    availableGradeLevels?: number[];
    error?: string;
    fromCache?: boolean;
  }> {
    try {
      // If not forcing refresh and we have valid cache, use it
      if (!forceRefresh && await this.hasValidCache()) {
        const cachedData = await this.getCachedData();
        if (cachedData) {
          // Save courses to storage for manual grade entry
          await this.saveCoursesToStorage(cachedData);
          
          // Determine current grade level and available grade levels
          const currentGradeLevel = getCurrentGradeLevel(cachedData);
          const availableGradeLevels = this.getAvailableGradeLevels(cachedData);
          
          const gpaData = processAcademicHistory(cachedData, gradeLevel);
          return {
            success: true,
            gpaData,
            rawData: cachedData,
            currentGradeLevel,
            availableGradeLevels,
            fromCache: true
          };
        }
      }

      console.log('Fetching fresh academic history from API...');
      // Fetch fresh data from API
      const result = await fetchAcademicHistory();
      
      if (result.success && result.data) {
        // Cache the fresh data
        await this.cacheData(result.data);
        console.log('Successfully fetched and cached academic history');
        
        // Save courses to storage for manual grade entry
        await this.saveCoursesToStorage(result.data);
        
        // Determine current grade level and available grade levels
        const currentGradeLevel = getCurrentGradeLevel(result.data);
        const availableGradeLevels = this.getAvailableGradeLevels(result.data);
        
        // Process and return
        const gpaData = processAcademicHistory(result.data, gradeLevel);
        return {
          success: true,
          gpaData,
          rawData: result.data,
          currentGradeLevel,
          availableGradeLevels,
          fromCache: false
        };
      }

      return {
        success: false,
        error: result.error || 'Failed to fetch academic history'
      };

    } catch (error: any) {
      console.error('Error in executeRequest:', error);
      return {
        success: false,
        error: error.message || 'Unknown error'
      };
    }
  }

    // Extract and save courses to AsyncStorage for manual grade entry
  private static async saveCoursesToStorage(academicData: any): Promise<void> {
    try {
      // Map grade numbers to names
      const gradeNames: Record<number, string> = {
        9: 'Freshman',
        10: 'Sophomore', 
        11: 'Junior',
        12: 'Senior'
      };

      // Process each grade level sequentially
      for (const [year, yearData] of Object.entries(academicData) as [string, any][]) {
        if (year !== 'alt' && yearData.grade >= 9 && yearData.grade <= 12) {
          const gradeName = gradeNames[yearData.grade];
          
          // Convert courses to the format expected by manual grade entry
          const courses = Object.entries(yearData.courses)
            .filter(([courseName, courseData]: [string, any]) => {
              // Only filter out courses with final grade "P" (Pass/Fail)
              // Keep ALL other courses, even those without grades (they can be manually entered)
              const hasValidName = courseName && typeof courseName === 'string';
              const isNotPassFail = courseData.finalGrade !== "P";
              
              return hasValidName && isNotPassFail;
            })
            .map(([courseName, courseData]: [string, any]) => ({
              name: courseName,
              level: this.getCourseLevel(courseName),
              terms: courseData.terms || '',
              grades: {
                sm1: courseData.sm1 || '',
                sm2: courseData.sm2 || '',
                finalGrade: courseData.finalGrade || '',
                pr1: courseData.pr1 || '',
                pr2: courseData.pr2 || '',
                pr3: courseData.pr3 || '',
                pr4: courseData.pr4 || '',
                pr5: courseData.pr5 || '',
                pr6: courseData.pr6 || '',
                pr7: courseData.pr7 || '',
                pr8: courseData.pr8 || '',
                rc1: courseData.rc1 || '',
                rc2: courseData.rc2 || '',
                rc3: courseData.rc3 || '',
                rc4: courseData.rc4 || ''
              }
            }))
            .sort((a, b) => a.name.localeCompare(b.name));

          const storageKey = `savedClasses-${gradeName}`;
          
          if (courses.length > 0) {
            await AsyncStorage.setItem(storageKey, JSON.stringify(courses));
          }
        }
      }
    } catch (error) {
      console.error('Error saving courses to storage:', error);
    }
  }

  // Helper method to convert Roman numerals to numbers and vice versa
  private static normalizeNumbers(text: string): string {
    const romanToNumber: { [key: string]: string } = {
      ' i': ' 1', ' ii': ' 2', ' iii': ' 3', ' iv': ' 4', ' v': ' 5', ' vi': ' 6'
    };
    const numberToRoman: { [key: string]: string } = {
      ' 1': ' i', ' 2': ' ii', ' 3': ' iii', ' 4': ' iv', ' 5': ' v', ' 6': ' vi'
    };
    
    let normalized = text;
    // Convert Roman numerals to numbers
    Object.entries(romanToNumber).forEach(([roman, number]) => {
      normalized = normalized.replace(new RegExp(roman, 'gi'), number);
    });
    // Also try converting numbers to Roman numerals for comparison
    Object.entries(numberToRoman).forEach(([number, roman]) => {
      normalized = normalized.replace(new RegExp(number, 'gi'), roman);
    });
    
    return normalized;
  }

  // Helper method to determine course level
  private static getCourseLevel(className: string): "AP" | "Honors" | "Regular" {
    if (!className || typeof className !== 'string' || className.trim() === '') {
      return "Regular";
    }
    
    const normalized = className.toLowerCase().trim();
    
    const apExceptions = ["multivariable calculus", "linear algebra", "stats 2: beyond ap statistics", "computer science 2", "computer science ii", "computer science 3", "computer science iii", "organic chemistry", "art historical methods"];
    const honorsExceptions = ["editorial leadership", "anatomy & physiology", "mentorship", "health science clinical", "robotics 2", "robotics ii", "robotics 3", "robotics iii", "swift coding", "business incubator", "engineering"];
    
    // First check for explicit AP pattern
    const hasAPKeyword = /\bap\b/.test(normalized);
    
    // Check AP exceptions - look for exact matches or close matches with Roman numeral normalization
    const isAPException = apExceptions.some(ex => {
      const normalizedCourse = this.normalizeNumbers(normalized);
      const normalizedEx = this.normalizeNumbers(ex);
      
      // Exact match (direct or after normalization)
      if (normalized === ex || normalizedCourse === normalizedEx) return true;
      
      // For longer exception names, check if course name contains the full exception
      if (ex.length > 10 && (normalized.includes(ex) || normalizedCourse.includes(normalizedEx))) return true;
      
      // For shorter exception names, be more strict - only match if they are very similar
      if (ex.length <= 10 && normalized.length > 5) {
        // Split into words and check for meaningful overlap
        const courseWords = normalizedCourse.split(/\s+/);
        const exWords = normalizedEx.split(/\s+/);
        
        // For courses like "computer science i" vs "computer science 2", they need to match more precisely
        if (courseWords.length >= 2 && exWords.length >= 2) {
          // Both must have same base words and the level must match exactly
          const courseBase = courseWords.slice(0, -1).join(' ');
          const courseLevel = courseWords[courseWords.length - 1];
          const exBase = exWords.slice(0, -1).join(' ');
          const exLevel = exWords[exWords.length - 1];
          
          if (courseBase === exBase && courseLevel === exLevel) return true;
        } else {
          // Single word courses - use exact match only
          if (ex.includes(normalized) || normalizedEx.includes(normalizedCourse)) return true;
        }
      }
      
      return false;
    });
    
    if (hasAPKeyword || isAPException) return "AP";
    
    // Check for Honors pattern
    const hasHonorsKeyword = /\bhonors?\b/.test(normalized);
    
    // Check Honors exceptions with Roman numeral normalization
    const isHonorsException = honorsExceptions.some(ex => {
      const normalizedCourse = this.normalizeNumbers(normalized);
      const normalizedEx = this.normalizeNumbers(ex);
      
      // Exact match (direct or after normalization)
      if (normalized === ex || normalizedCourse === normalizedEx) return true;
      
      // For longer exception names, check if course name contains the full exception
      if (ex.length > 10 && (normalized.includes(ex) || normalizedCourse.includes(normalizedEx))) return true;
      
      // For shorter exception names, be more strict - only match if they are very similar
      if (ex.length <= 10 && normalized.length > 5) {
        // Split into words and check for meaningful overlap
        const courseWords = normalizedCourse.split(/\s+/);
        const exWords = normalizedEx.split(/\s+/);
        
        // For courses like "robotics i" vs "robotics 2", they need to match more precisely
        if (courseWords.length >= 2 && exWords.length >= 2) {
          // Both must have same base word and the level must match exactly
          const courseBase = courseWords[0];
          const courseLevel = courseWords[1];
          const exBase = exWords[0];
          const exLevel = exWords[1];
          
          if (courseBase === exBase && courseLevel === exLevel) return true;
        } else {
          // Single word courses - use exact match only
          if (ex.includes(normalized) || normalizedEx.includes(normalizedCourse)) return true;
        }
      }
      
      return false;
    });
    
    if (hasHonorsKeyword || isHonorsException) return "Honors";
    
    return "Regular";
  }

  // Clear cached data
  public static async clearCache(): Promise<void> {
    try {
      await AsyncStorage.removeItem(this.CACHE_KEY);
    } catch (error) {
      console.error('Error clearing cache:', error);
    }
  }

  // Get cache info for debugging
  public static async getCacheInfo(): Promise<{
    exists: boolean;
    academicYear?: string;
    timestamp?: number;
    age?: number;
  }> {
    try {
      const cached = await AsyncStorage.getItem(this.CACHE_KEY);
      if (!cached) {
        return { exists: false };
      }

      const cachedData: CachedAcademicData = JSON.parse(cached);
      return {
        exists: true,
        academicYear: cachedData.academicYear,
        timestamp: cachedData.timestamp,
        age: Date.now() - cachedData.timestamp
      };
    } catch (error) {
      console.error('Error getting cache info:', error);
      return { exists: false };
    }
  }
}
