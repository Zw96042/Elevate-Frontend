import { useCallback, useEffect, useState, useRef } from 'react';
import { DeviceEventEmitter } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
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

// Function to extract grade levels from course data
const extractGradeLevelsFromCourseData = (coursesData: any[]): { currentGrade: number | null, availableGrades: number[] } => {
  if (!coursesData || coursesData.length === 0) {
    return { currentGrade: null, availableGrades: [] };
  }

  const gradeYears = new Set<number>();
  let mostRecentGrade: number | null = null;
  
  // Extract all grade years from course data
  coursesData.forEach(course => {
    if (course.gradeYear && typeof course.gradeYear === 'number') {
      gradeYears.add(course.gradeYear);
      // Assume the highest grade year is the current/most recent
      if (mostRecentGrade === null || course.gradeYear > mostRecentGrade) {
        mostRecentGrade = course.gradeYear;
      }
    }
  });

  return {
    currentGrade: mostRecentGrade,
    availableGrades: Array.from(gradeYears).sort()
  };
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
  // Start with Senior (12th grade) as the current default - most recent grade first
  const [currentGradeLevel, setCurrentGradeLevel] = useState<GradeLevel>('Senior');
  const [availableGradeLevels, setAvailableGradeLevels] = useState<GradeLevel[]>(['Senior']);
  const [isLoading, setIsLoading] = useState(true);
  const hasInitializedRef = useRef(false);

  console.log('🎓 useGradeLevel hook - Current state:', {
    currentGradeLevel,
    availableGradeLevels,
    isLoading,
    hasInitialized: hasInitializedRef.current
  });

  const GRADE_LEVEL_CACHE_KEY = 'gradeLevelCache';
  const GRADE_LEVEL_CACHE_DURATION = 30 * 24 * 60 * 60 * 1000; // 30 days in milliseconds

  // Load cached grade level data
  const loadCachedGradeLevelData = useCallback(async (): Promise<CachedGradeLevelData | null> => {
    try {
      console.log('🔍 Attempting to load cached grade level data...');
      const cachedData = await AsyncStorage.getItem(GRADE_LEVEL_CACHE_KEY);
      console.log('📱 Raw cached data:', cachedData);
      
      if (!cachedData) {
        console.log('❌ No cached data found');
        return null;
      }

      const parsedData: CachedGradeLevelData = JSON.parse(cachedData);
      console.log('📋 Parsed cached data:', parsedData);
      
      const now = Date.now();
      const currentAcademicYear = getCurrentAcademicYear();
      console.log('📅 Cache validation:', {
        now,
        cacheTimestamp: parsedData.timestamp,
        cacheAge: now - parsedData.timestamp,
        maxAge: GRADE_LEVEL_CACHE_DURATION,
        isWithinDuration: now - parsedData.timestamp < GRADE_LEVEL_CACHE_DURATION,
        currentAcademicYear,
        cachedAcademicYear: parsedData.academicYear,
        isSameYear: parsedData.academicYear === currentAcademicYear
      });

      // Check if cache is still valid (within duration and same academic year)
      if (
        now - parsedData.timestamp < GRADE_LEVEL_CACHE_DURATION &&
        parsedData.academicYear === currentAcademicYear
      ) {
        console.log('✅ Cache is valid, returning cached data');
        return parsedData;
      }

      // Cache is expired or from different academic year
      console.log('⚠️ Cache is expired or from different academic year, removing...');
      await AsyncStorage.removeItem(GRADE_LEVEL_CACHE_KEY);
      return null;
    } catch (error) {
      console.error('❌ Error loading cached grade level data:', error);
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

      console.log('💾 Saving grade level data to cache:', cacheData);
      await AsyncStorage.setItem(GRADE_LEVEL_CACHE_KEY, JSON.stringify(cacheData));
      console.log('✅ Grade level data cached successfully');
    } catch (error) {
      console.error('❌ Error saving grade level data to cache:', error);
    }
  }, []);

  const loadGradeFromCourseData = useCallback(async (coursesData?: any[]) => {
    console.log('🌐 loadGradeFromCourseData called with coursesData length:', coursesData?.length || 0);
    setIsLoading(true);
    
    try {
      // If we have course data passed in, skip cache and extract directly from it
      if (coursesData && coursesData.length > 0) {
        console.log('� Extracting grade levels from provided course data (skipping cache)...');
        console.log('� Sample course data:', coursesData.slice(0, 3).map(c => ({
          courseName: c.courseName,
          gradeYear: c.gradeYear,
          academicYear: c.academicYear
        })));
        
        const { currentGrade, availableGrades } = extractGradeLevelsFromCourseData(coursesData);
        console.log('📊 Extracted grades:', { currentGrade, availableGrades });
        
        if (currentGrade && availableGrades.length > 0) {
          const currentGradeName = getGradeLevelName(currentGrade);
          const availableGradeNames = availableGrades.map(getGradeLevelName);
          
          // Add "All Time" if we have multiple grades
          if (availableGradeNames.length > 1) {
            availableGradeNames.push('All Time');
          }
          
          console.log('✅ Successfully extracted grade levels from course data:', {
            currentGradeName,
            availableGradeNames
          });
          
          setCurrentGradeLevel(currentGradeName);
          setAvailableGradeLevels(availableGradeNames);

          // Cache the data for future use
          await saveCachedGradeLevelData(currentGradeName, availableGradeNames);
          setIsLoading(false);
          return;
        } else {
          console.log('⚠️ No valid grade levels extracted from course data');
        }
      }
      
      // No course data provided, try to load from cache
      console.log('📱 No course data provided, trying to load from cache...');
      const cachedData = await loadCachedGradeLevelData();
      if (cachedData) {
        console.log('📱 Loading grade levels from cache:', cachedData);
        setCurrentGradeLevel(cachedData.currentGradeLevel);
        setAvailableGradeLevels(cachedData.availableGradeLevels);
        setIsLoading(false);
        return;
      }

      // Check if we have credentials first
      console.log('🔐 Checking for credentials...');
      const hasCredentials = await SkywardAuth.hasCredentials();
      console.log('🔐 Has credentials:', hasCredentials);
      if (!hasCredentials) {
        // Fallback to default values if no credentials - default to Senior (most recent)
        console.log('❌ No credentials found, using default fallback values with Senior selected');
        const fallbackGrades: GradeLevel[] = ['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time'];
        setCurrentGradeLevel('Senior');
        setAvailableGradeLevels(fallbackGrades);
        setIsLoading(false);
        return;
      }

      // Final fallback - provide all grade levels with Senior selected
      console.log('📊 Using fallback: providing all grade levels with Senior selected');
      const fallbackGrades: GradeLevel[] = ['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time'];
      setCurrentGradeLevel('Senior');
      setAvailableGradeLevels(fallbackGrades);
      
    } catch (error) {
      console.error('❌ Error in loadGradeFromCourseData:', error);
      // Error fallback - provide all grade levels with Senior selected
      const fallbackGrades: GradeLevel[] = ['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time'];
      setCurrentGradeLevel('Senior');
      setAvailableGradeLevels(fallbackGrades);
    } finally {
      console.log('🏁 Setting isLoading to false');
      setIsLoading(false);
    }
  }, [loadCachedGradeLevelData, saveCachedGradeLevelData]);

  // Method to force refresh grade level data (clears cache)
  const refreshGradeLevelData = useCallback(async (coursesData?: any[]) => {
    try {
      await AsyncStorage.removeItem(GRADE_LEVEL_CACHE_KEY);
      console.log('🗑️ Grade level cache cleared');
      await loadGradeFromCourseData(coursesData);
    } catch (error) {
      console.error('Error refreshing grade level data:', error);
    }
  }, [loadGradeFromCourseData]);

  useEffect(() => {
    if (!hasInitializedRef.current) {
      console.log('🏁 useGradeLevel useEffect triggered - calling loadGradeFromCourseData (first time)');
      hasInitializedRef.current = true;
      loadGradeFromCourseData();
    } else {
      console.log('🚫 useGradeLevel useEffect triggered but already initialized, skipping');
    }
  }, [loadGradeFromCourseData]);

  // Listen for credential updates to refresh grade level data
  useEffect(() => {
    const credentialsListener = DeviceEventEmitter.addListener('credentialsAdded', async () => {
      console.log('🔄 Credentials updated, clearing cache and resetting grade level state');
      // Clear the cache
      await AsyncStorage.removeItem(GRADE_LEVEL_CACHE_KEY);
      console.log('🗑️ Grade level cache cleared');
      
      // Reset to default state to prevent showing old user's grade level - default to Senior (most recent)
      console.log('🔄 Resetting to default Senior state');
      setCurrentGradeLevel('Senior'); // Reset to default (most recent grade)
      setAvailableGradeLevels(['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time']); // Provide all options
      setIsLoading(true); // Set loading while we wait for new data
      
      // Wait a bit for new course data to be fetched, then reload grade level
      console.log('⏳ Waiting for new course data...');
      setTimeout(async () => {
        console.log('🔄 Attempting to load grade level from new course data');
        await loadGradeFromCourseData();
      }, 500); // Give time for course data to refresh
    });

    return () => {
      credentialsListener.remove();
    };
  }, [loadGradeFromCourseData]);

  // Static method to clear grade level cache (useful for debugging)
  const clearGradeLevelCache = useCallback(async () => {
    try {
      await AsyncStorage.removeItem(GRADE_LEVEL_CACHE_KEY);
      console.log('🗑️ Grade level cache cleared manually');
    } catch (error) {
      console.error('Error clearing grade level cache:', error);
    }
  }, []);

  // Debug function to show current cache state
  const debugCacheState = useCallback(async () => {
    try {
      const cachedData = await AsyncStorage.getItem(GRADE_LEVEL_CACHE_KEY);
      console.log('🔍 DEBUG: Current cache state:', cachedData);
      if (cachedData) {
        const parsed = JSON.parse(cachedData);
        console.log('🔍 DEBUG: Parsed cache data:', parsed);
      }
    } catch (error) {
      console.error('🔍 DEBUG: Error reading cache:', error);
    }
  }, []);

  return { 
    currentGradeLevel, 
    availableGradeLevels, 
    isLoading,
    refreshGradeLevelData,
    clearGradeLevelCache,
    debugCacheState,
    loadGradeFromCourseData
  };
};