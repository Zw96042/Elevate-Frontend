import { useCallback, useEffect, useState } from 'react';
import { DeviceEventEmitter } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AcademicHistoryManager } from '@/lib/academicHistoryManager';
import { SkywardAuth } from '@/lib/skywardAuthInfo';

export type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

// Convert grade number to grade level name
const getGradeLevelName = (gradeNumber: number): GradeLevel => {
  switch (gradeNumber) {
    case 9: return 'Freshman';
    case 10: return 'Sophomore';
    case 11: return 'Junior';
    case 12: return 'Senior';
    default: return 'Freshman';
  }
};

interface CachedGradeLevelData {
  currentGradeLevel: GradeLevel;
  availableGradeLevels: GradeLevel[];
  timestamp: number;
  academicYear: string;
}

// Get current academic year for cache validation
const getCurrentAcademicYear = (): string => {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();
  
  // Academic year typically starts in August/September
  if (month >= 7) { // August or later
    return `${year}-${year + 1}`;
  } else { // Before August
    return `${year - 1}-${year}`;
  }
};

export const useGradeLevel = () => {
  // Start with Sophomore (10th grade) as the current default instead of Freshman
  const [currentGradeLevel, setCurrentGradeLevel] = useState<GradeLevel>('Sophomore');
  const [availableGradeLevels, setAvailableGradeLevels] = useState<GradeLevel[]>(['Sophomore']);
  const [isLoading, setIsLoading] = useState(true);

  const GRADE_LEVEL_CACHE_KEY = 'gradeLevelCache';
  const GRADE_LEVEL_CACHE_DURATION = 30 * 24 * 60 * 60 * 1000; // 30 days in milliseconds

  // Load cached grade level data
  const loadCachedGradeLevelData = useCallback(async (): Promise<CachedGradeLevelData | null> => {
    try {
      const cachedData = await AsyncStorage.getItem(GRADE_LEVEL_CACHE_KEY);
      if (!cachedData) return null;

      const parsedData: CachedGradeLevelData = JSON.parse(cachedData);
      const now = Date.now();
      const currentAcademicYear = getCurrentAcademicYear();

      // Check if cache is still valid (within duration and same academic year)
      if (
        now - parsedData.timestamp < GRADE_LEVEL_CACHE_DURATION &&
        parsedData.academicYear === currentAcademicYear
      ) {
        return parsedData;
      }

      // Cache is expired or from different academic year
      await AsyncStorage.removeItem(GRADE_LEVEL_CACHE_KEY);
      return null;
    } catch (error) {
      console.error('Error loading cached grade level data:', error);
      return null;
    }
  }, []);

  // Save grade level data to cache
  const saveCachedGradeLevelData = useCallback(async (
    currentGrade: GradeLevel,
    availableGrades: GradeLevel[]
  ) => {
    try {
      const cacheData: CachedGradeLevelData = {
        currentGradeLevel: currentGrade,
        availableGradeLevels: availableGrades,
        timestamp: Date.now(),
        academicYear: getCurrentAcademicYear()
      };

      await AsyncStorage.setItem(GRADE_LEVEL_CACHE_KEY, JSON.stringify(cacheData));
      console.log('💾 Grade level data cached successfully');
    } catch (error) {
      console.error('Error saving grade level data to cache:', error);
    }
  }, []);

  const loadGradeFromAcademicHistory = useCallback(async () => {
    setIsLoading(true);
    
    try {
      // First, try to load from cache
      const cachedData = await loadCachedGradeLevelData();
      if (cachedData) {
        console.log('📱 Loading grade levels from cache');
        setCurrentGradeLevel(cachedData.currentGradeLevel);
        setAvailableGradeLevels(cachedData.availableGradeLevels);
        setIsLoading(false);
        return;
      }

      // Check if we have credentials first
      const hasCredentials = await SkywardAuth.hasCredentials();
      if (!hasCredentials) {
        // Fallback to stored grade level if no credentials
        setIsLoading(false);
        return;
      }

      console.log('🌐 Loading grade levels from API');
      // Get academic history to determine current grade level
      const result = await AcademicHistoryManager.getAcademicHistory(false);
      if (result.success && result.currentGradeLevel && result.availableGradeLevels) {
        const currentGrade = getGradeLevelName(result.currentGradeLevel);
        
        // Convert available grade numbers to grade level names, plus "All Time"
        const availableGrades = result.availableGradeLevels.map(getGradeLevelName);
        if (availableGrades.length > 1) {
          availableGrades.push('All Time');
        }

        setCurrentGradeLevel(currentGrade);
        setAvailableGradeLevels(availableGrades);

        // Cache the data for future use
        await saveCachedGradeLevelData(currentGrade, availableGrades);
      }
    } catch (error) {
      console.error('Error loading grade level from academic history:', error);
    } finally {
      setIsLoading(false);
    }
  }, [loadCachedGradeLevelData, saveCachedGradeLevelData]);

  // Method to force refresh grade level data (clears cache)
  const refreshGradeLevelData = useCallback(async () => {
    try {
      await AsyncStorage.removeItem(GRADE_LEVEL_CACHE_KEY);
      console.log('🗑️ Grade level cache cleared');
      await loadGradeFromAcademicHistory();
    } catch (error) {
      console.error('Error refreshing grade level data:', error);
    }
  }, [loadGradeFromAcademicHistory]);

  useEffect(() => {
    loadGradeFromAcademicHistory();
  }, [loadGradeFromAcademicHistory]);

  // Listen for credential updates to refresh grade level data
  useEffect(() => {
    const credentialsListener = DeviceEventEmitter.addListener('credentialsAdded', async () => {
      console.log('🔄 Credentials updated, refreshing grade level data');
      await refreshGradeLevelData();
    });

    return () => {
      credentialsListener.remove();
    };
  }, [refreshGradeLevelData]);

  // Static method to clear grade level cache (useful for debugging)
  const clearGradeLevelCache = useCallback(async () => {
    try {
      await AsyncStorage.removeItem(GRADE_LEVEL_CACHE_KEY);
      console.log('🗑️ Grade level cache cleared manually');
    } catch (error) {
      console.error('Error clearing grade level cache:', error);
    }
  }, []);

  return { 
    currentGradeLevel, 
    availableGradeLevels, 
    isLoading,
    refreshGradeLevelData,
    clearGradeLevelCache
  };
};