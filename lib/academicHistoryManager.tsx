// lib/academicHistoryManager.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { fetchAcademicHistory } from './academicHistoryClient';
import { processAcademicHistory } from '@/utils/academicHistoryProcessor';

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
  public static async getAcademicHistory(forceRefresh: boolean = false): Promise<{
    success: boolean;
    gpaData?: Record<string, GPAData>;
    rawData?: any;
    error?: string;
    fromCache?: boolean;
  }> {
    // If there's already an active request and we're not forcing refresh, wait for it
    if (!forceRefresh && this.activeRequest) {
      console.log('Academic history request already in progress, waiting...');
      return await this.activeRequest;
    }

    // Create the request promise
    const requestPromise = this.executeRequest(forceRefresh);
    
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

  private static async executeRequest(forceRefresh: boolean): Promise<{
    success: boolean;
    gpaData?: Record<string, GPAData>;
    rawData?: any;
    error?: string;
    fromCache?: boolean;
  }> {
    try {
      // If not forcing refresh and we have valid cache, use it
      if (!forceRefresh && await this.hasValidCache()) {
        const cachedData = await this.getCachedData();
        if (cachedData) {
          console.log('Using cached academic history data');
          const gpaData = processAcademicHistory(cachedData);
          return {
            success: true,
            gpaData,
            rawData: cachedData,
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
        
        // Process and return
        const gpaData = processAcademicHistory(result.data);
        return {
          success: true,
          gpaData,
          rawData: result.data,
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

  // Clear cache (useful for debugging or manual refresh)
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
