/**
 * Centralized Caching System
 * Handles data caching with TTL, validation, and automatic cleanup
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { CacheItem, AsyncStorageKeys } from '@/interfaces/interfaces';

const DEFAULT_TTL = 5 * 60 * 1000; // 5 minutes
const CACHE_PREFIX = 'cache_';

export class CacheManager {
  /**
   * Store data in cache with optional TTL
   */
  static async set<T>(key: string, data: T, ttl: number = DEFAULT_TTL): Promise<void> {
    try {
      const cacheItem: CacheItem<T> = {
        data,
        timestamp: Date.now(),
        ttl,
      };

      await AsyncStorage.setItem(
        `${CACHE_PREFIX}${key}`,
        JSON.stringify(cacheItem)
      );
    } catch (error) {
      console.error(`Failed to cache data for key ${key}:`, error);
      throw new Error(`Failed to cache data: ${error}`);
    }
  }

  /**
   * Retrieve data from cache
   */
  static async get<T>(key: string): Promise<T | null> {
    try {
      const cachedData = await AsyncStorage.getItem(`${CACHE_PREFIX}${key}`);
      if (!cachedData) {
        return null;
      }

      const cacheItem: CacheItem<T> = JSON.parse(cachedData);
      
      // Check if cache has expired
      if (this.isExpired(cacheItem)) {
        await this.delete(key);
        return null;
      }

      return cacheItem.data;
    } catch (error) {
      console.error(`Failed to get cached data for key ${key}:`, error);
      return null;
    }
  }

  /**
   * Check if cached data exists and is valid
   */
  static async has(key: string): Promise<boolean> {
    try {
      const cachedData = await AsyncStorage.getItem(`${CACHE_PREFIX}${key}`);
      if (!cachedData) {
        return false;
      }

      const cacheItem: CacheItem<any> = JSON.parse(cachedData);
      
      if (this.isExpired(cacheItem)) {
        await this.delete(key);
        return false;
      }

      return true;
    } catch (error) {
      console.error(`Failed to check cache for key ${key}:`, error);
      return false;
    }
  }

  /**
   * Delete cached data
   */
  static async delete(key: string): Promise<void> {
    try {
      await AsyncStorage.removeItem(`${CACHE_PREFIX}${key}`);
    } catch (error) {
      console.error(`Failed to delete cache for key ${key}:`, error);
    }
  }

  /**
   * Clear all cached data
   */
  static async clear(): Promise<void> {
    try {
      const allKeys = await AsyncStorage.getAllKeys();
      const cacheKeys = allKeys.filter(key => key.startsWith(CACHE_PREFIX));
      await AsyncStorage.multiRemove(cacheKeys);
    } catch (error) {
      console.error('Failed to clear cache:', error);
    }
  }

  /**
   * Get cache info (size, count, etc.)
   */
  static async getInfo(): Promise<{
    count: number;
    keys: string[];
    totalSize: number;
  }> {
    try {
      const allKeys = await AsyncStorage.getAllKeys();
      const cacheKeys = allKeys.filter(key => key.startsWith(CACHE_PREFIX));
      
      let totalSize = 0;
      for (const key of cacheKeys) {
        const data = await AsyncStorage.getItem(key);
        if (data) {
          totalSize += data.length;
        }
      }

      return {
        count: cacheKeys.length,
        keys: cacheKeys.map(key => key.replace(CACHE_PREFIX, '')),
        totalSize,
      };
    } catch (error) {
      console.error('Failed to get cache info:', error);
      return { count: 0, keys: [], totalSize: 0 };
    }
  }

  /**
   * Clean up expired cache entries
   */
  static async cleanup(): Promise<number> {
    try {
      const allKeys = await AsyncStorage.getAllKeys();
      const cacheKeys = allKeys.filter(key => key.startsWith(CACHE_PREFIX));
      
      let cleanedCount = 0;
      
      for (const key of cacheKeys) {
        try {
          const data = await AsyncStorage.getItem(key);
          if (data) {
            const cacheItem: CacheItem<any> = JSON.parse(data);
            if (this.isExpired(cacheItem)) {
              await AsyncStorage.removeItem(key);
              cleanedCount++;
            }
          }
        } catch (error) {
          // If we can't parse the item, remove it
          await AsyncStorage.removeItem(key);
          cleanedCount++;
        }
      }

      return cleanedCount;
    } catch (error) {
      console.error('Failed to cleanup cache:', error);
      return 0;
    }
  }

  /**
   * Check if cache item has expired
   */
  private static isExpired<T>(cacheItem: CacheItem<T>): boolean {
    const now = Date.now();
    const ttl = cacheItem.ttl || DEFAULT_TTL;
    return now - cacheItem.timestamp > ttl;
  }

  /**
   * Get or set data with a function
   */
  static async getOrSet<T>(
    key: string,
    fetchFunction: () => Promise<T>,
    ttl: number = DEFAULT_TTL
  ): Promise<T> {
    // Try to get from cache first
    const cachedData = await this.get<T>(key);
    if (cachedData !== null) {
      return cachedData;
    }

    // If not in cache, fetch and store
    const freshData = await fetchFunction();
    await this.set(key, freshData, ttl);
    return freshData;
  }

  /**
   * Cache keys for common data types
   */
  static readonly KEYS = {
    ACADEMIC_HISTORY: 'academic_history',
    MESSAGES: 'messages',
    GRADE_INFO: 'grade_info',
    REPORT_CARD: 'report_card',
    UNIFIED_DATA: 'unified_data',
    GPA_DATA: 'gpa_data',
  } as const;
}
