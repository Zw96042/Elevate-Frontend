import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, TouchableOpacity, FlatList, RefreshControl, DeviceEventEmitter } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import ClassCard from '@/components/ClassCard';
import SkeletonClassCard from '@/components/SkeletonClassCard';
import ErrorDisplay from '@/components/ErrorDisplay';
import LoginPrompt from '@/components/LoginPrompt';
import { SkywardAuth } from '@/lib';
import { useBottomSheet, BottomSheetProvider } from '@/context/BottomSheetContext'
import { useSettingSheet } from '@/context/SettingSheetContext';
import { useUnifiedData } from '@/context/UnifiedDataContext';
import { useGradeLevel } from '@/hooks/useGradeLevel';
import { logger, Modules } from '@/lib/utils/logger';
import { shouldBlockCourseError, transformCourseData } from '@/lib/utils/course-card-transform';


const filterCoursesBySemester = (courses: any[], selectedTerm: string) => {
  // Map display terms to semester filtering terms
  const termMapping: Record<string, string> = {
    'Q1 Grades': 'RC1',
    'Q2 Grades': 'RC2', 
    'SM1 Grade': 'SM1',
    'Q3 Grades': 'RC3',
    'Q4 Grades': 'RC4',
    'SM2 Grades': 'SM2'
  };
  
  // Get the actual term code for filtering
  const filterTerm = termMapping[selectedTerm] || selectedTerm;
  
  // Define term to semester mapping
  const fallTerms = ['RC1', 'RC2', 'SM1'];
  const springTerms = ['RC3', 'RC4', 'SM2'];
  
  // If term is not specified or is "All", return all courses
  if (!filterTerm || filterTerm === 'All') {
    return courses;
  }
  
  // Determine which semester to filter for
  let targetSemesters: string[] = [];
  
  if (fallTerms.includes(filterTerm)) {
    targetSemesters = ['fall', 'both'];
  } else if (springTerms.includes(filterTerm)) {
    targetSemesters = ['spring', 'both'];
  } else {
    // If it's not a recognized term, return all courses
    return courses;
  }
  
  // Filter courses based on semester property
  return courses.filter(course => {
    // If course doesn't have semester property, include it (backwards compatibility)
    if (!course.semester) {
      return true;
    }
    
    return targetSemesters.includes(course.semester);
  });
};

export default function Index() {
  const { bottomSheetRef, selectedCategory, setSelectedCategory } = useBottomSheet();
  const { settingSheetRef } = useSettingSheet();
  const { coursesData, loading, error, refreshCourses } = useUnifiedData();
  const { currentGradeLevel, loadGradeFromCourseData } = useGradeLevel();
  const [filteredCourses, setFilteredCourses] = useState<any[]>([]);
  const [hasFilteredOnce, setHasFilteredOnce] = useState(false);
  const [lastFilteredGradeLevel, setLastFilteredGradeLevel] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [hasCredentials, setHasCredentials] = useState(false);
  const [hasCheckedCredentials, setHasCheckedCredentials] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);

  // Check credentials on mount
  useEffect(() => {
    const checkCredentials = async () => {
      console.log('🔐 [Index] Checking credentials...');
      const hasCreds = await SkywardAuth.hasCredentials();
      console.log('🔐 [Index] Credentials check complete:', { hasCreds });
      setHasCredentials(hasCreds);
      setHasCheckedCredentials(true);
    };
    checkCredentials();
  }, []);

  // Update grade level when course data changes
  useEffect(() => {
    if (coursesData && coursesData.length > 0) {
      logger.info(Modules.PAGE_HOME, `Course data changed, updating grade level (${coursesData.length} courses)`);
      loadGradeFromCourseData(coursesData);
    }
  }, [coursesData, loadGradeFromCourseData]);

  // Listen for credential updates
  useEffect(() => {
    const credentialsListener = DeviceEventEmitter.addListener('credentialsAdded', async () => {
      logger.info(Modules.PAGE_HOME, 'Credentials added');
      setLocalError(null);
      setHasCredentials(true);
    });
    const invalidCredentialsListener = DeviceEventEmitter.addListener('credentialsInvalid', () => {
      setHasCredentials(false);
      setFilteredCourses([]);
      setLocalError(null);
    });

    return () => {
      credentialsListener.remove();
      invalidCredentialsListener.remove();
    };
  }, []);

  // No need for local loadCourses, use refreshCourses from context

  // Effect to filter courses when selectedCategory or currentGradeLevel changes
  useEffect(() => {
    console.log('🔄 [Index] Filter effect triggered:', {
      hasCoursesData: !!coursesData,
      coursesDataLength: coursesData?.length || 0,
      currentGradeLevel,
      selectedCategory
    });
    
    // Don't mark as filtered if we don't have data yet
    if (!coursesData) {
      console.log('⏳ [Index] No coursesData yet, skipping filter');
      return;
    }
    
    logger.debug(Modules.PAGE_HOME, 'Filtering courses', {
      grade: currentGradeLevel,
      term: selectedCategory,
      totalCourses: coursesData?.length || 0
    });
    
    // Filter by current grade level first, then by selected term
    let filteredRawCourses = coursesData || [];
    if (coursesData && currentGradeLevel && currentGradeLevel !== 'All Time') {
      // Map grade level to gradeYear
      const gradeMap: Record<string, number> = {
        'Freshman': 9,
        'Sophomore': 10,
        'Junior': 11,
        'Senior': 12
      };
      const gradeYear = gradeMap[currentGradeLevel as keyof typeof gradeMap];
      
      filteredRawCourses = currentGradeLevel === 'Current'
        ? coursesData.filter((c: any) => c.gradeYear == null)
        : coursesData.filter((c: any) => c.gradeYear === gradeYear);
      logger.debug(Modules.PAGE_HOME, `Filtered to ${filteredRawCourses.length} courses for grade ${gradeYear}`);
    }
    
    // Transform and filter by semester
    const transformedCourses = transformCourseData(filteredRawCourses);
    const filtered = filterCoursesBySemester(transformedCourses, selectedCategory);
    
    logger.debug(Modules.PAGE_HOME, `After semester filter: ${filtered.length} courses`);
    console.log('✅ [Index] Filter complete:', {
      filteredCount: filtered.length,
      settingHasFilteredOnce: true,
      forGradeLevel: currentGradeLevel
    });
    setFilteredCourses(filtered);
    setLastFilteredGradeLevel(currentGradeLevel);
    setHasFilteredOnce(true);
  }, [coursesData, selectedCategory, currentGradeLevel]);

  const onRefresh = useCallback(async () => {
    logger.info(Modules.PAGE_HOME, 'Pull-to-refresh triggered');
    setRefreshing(true);
    setLocalError(null);
    try {
      await refreshCourses(true);
      logger.success(Modules.PAGE_HOME, 'Courses refreshed successfully');
    } catch (error) {
      logger.error(Modules.PAGE_HOME, 'Failed to refresh courses', error);
      setLocalError('Unable to refresh courses. Please check your connection and try again.');
    }
    setRefreshing(false);
  }, [refreshCourses]);

  useEffect(() => {
    // Only trigger refresh if we have no data AND context is not already loading
    // AND there's no error at all (to prevent infinite loops on auth failures)
    if (!coursesData && !loading && !error) {
      console.log('🔄 [Index] Triggering refreshCourses because no data');
      setHasFilteredOnce(false); // Reset filter state when starting fresh fetch
      refreshCourses();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [coursesData, loading]); // Remove error from dependencies to prevent infinite loop

  // Show login prompt if credentials are not set (only after we've checked)
  if (hasCheckedCredentials && !hasCredentials) {
    return (
      <View className="flex-1 bg-primary">
        <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
          <Text className="text-white text-3xl font-bold">Courses</Text>
          <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
            <Ionicons name='cog-outline' color={'#fff'} size={26} />
          </TouchableOpacity>
        </View>
        <View className="flex-1 mt-20">
          <LoginPrompt
            message="Please log in with your Skyward credentials to view your courses."
            onLoginPress={() => settingSheetRef.current?.snapToIndex(0)}
          />
        </View>
      </View>
    );
  }

  // Show error display for non-credential errors (only when not loading and we have checked credentials)
  if (shouldBlockCourseError({
    error,
    localError,
    loading,
    checkedCredentials: hasCheckedCredentials,
    hasCourseSnapshot: coursesData !== null,
  })) {
    return (
      <View className="flex-1 bg-primary">
        <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
          <Text className="text-white text-3xl font-bold">Courses</Text>
          <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
            <Ionicons name='cog-outline' color={'#fff'} size={26} />
          </TouchableOpacity>
        </View>
        <View className="flex-1 mt-24">
          <ErrorDisplay
            error={localError || error || 'Unable to load courses'}
            onRetry={async () => {
              setLocalError(null);
              await onRefresh();
            }}
            title="Couldn't load courses"
          />
        </View>
      </View>
    );
  }

  // Determine if we should show loading state
  // Show loading if:
  // 1. Context is loading
  // 2. Haven't checked credentials yet
  // 3. Have credentials but no coursesData yet (still fetching)
  // 4. Have coursesData but haven't filtered yet
  // 5. Grade level has changed but filter hasn't caught up yet
  // 6. Have filtered but got 0 results AND grade level doesn't match available data
  //    (this prevents flicker when cached grade level doesn't match new data)
  const gradeMap: Record<string, number> = {
    'Freshman': 9,
    'Sophomore': 10,
    'Junior': 11,
    'Senior': 12
  };
  const currentGradeYear = gradeMap[currentGradeLevel as keyof typeof gradeMap];
  const hasMatchingGradeInData = currentGradeLevel === 'All Time' ||
    (currentGradeLevel === 'Current'
      ? (coursesData?.some((c: any) => c.gradeYear == null) ?? false)
      : (coursesData?.some((c: any) => c.gradeYear === currentGradeYear) ?? false));
  
  // Check if filter is stale (grade level changed but filter hasn't run yet)
  const isFilterStale = hasFilteredOnce && lastFilteredGradeLevel !== currentGradeLevel;
  
  const isLoadingState = loading || 
    !hasCheckedCredentials || 
    (hasCredentials && !coursesData) ||
    (hasCredentials && coursesData && !hasFilteredOnce) ||
    isFilterStale ||
    (hasFilteredOnce && filteredCourses.length === 0 && coursesData && coursesData.length > 0 && !hasMatchingGradeInData);

  // Debug logging for state transitions
  console.log('🏠 [Index] Render state:', {
    loading,
    hasCheckedCredentials,
    hasCredentials,
    hasCoursesData: !!coursesData,
    coursesDataLength: coursesData?.length || 0,
    hasFilteredOnce,
    lastFilteredGradeLevel,
    currentGradeLevel,
    isFilterStale,
    filteredCoursesLength: filteredCourses.length,
    isLoadingState,
    error: error || null,
    localError: localError || null,
    hasMatchingGradeInData,
    // Show which condition is causing loading
    loadingReason: loading ? 'context loading' : 
      !hasCheckedCredentials ? 'credentials not checked' :
      (hasCredentials && !coursesData) ? 'has creds but no data' :
      (hasCredentials && coursesData && !hasFilteredOnce) ? 'has data but not filtered' :
      isFilterStale ? 'filter stale - grade level changed' :
      (hasFilteredOnce && filteredCourses.length === 0 && coursesData && coursesData.length > 0 && !hasMatchingGradeInData) ? 'grade level mismatch - waiting for sync' :
      'not loading'
  });

  // Show error display for non-credential errors
  if (localError && !coursesData) {
    return (
      <View className="flex-1 bg-primary">
        <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
          <Text className="text-white text-3xl font-bold">Courses</Text>
          <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
            <Ionicons name='cog-outline' color={'#fff'} size={26} />
          </TouchableOpacity>
        </View>
        <View className="flex-1 mt-24">
          <ErrorDisplay
            error={localError}
            onRetry={async () => {
              setLocalError(null);
              await onRefresh();
            }}
            title="Couldn't load courses"
          />
        </View>
      </View>
    );
  }

  return (
    
      <View className="flex-1 bg-primary">
        <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
          <Text className="text-white text-3xl font-bold">Courses</Text>
          <TouchableOpacity
            onPress={() => settingSheetRef.current?.snapToIndex(0)}
          >
            <Ionicons name='cog-outline' color={'#fff'} size={26} />
          </TouchableOpacity>
        </View>
        <FlatList
          className=''
          data={isLoadingState ? Array.from({ length: 7 }) : filteredCourses}
          showsVerticalScrollIndicator={false}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
          }
          ListHeaderComponent={
            <>
              {(error || localError) && coursesData && (
                <View
                  accessibilityRole="alert"
                  className="mx-5 mt-3 rounded-xl bg-amber-100 px-4 py-3"
                >
                  <Text className="text-sm font-medium text-amber-900">
                    Couldn&apos;t refresh. Showing your last saved grades.
                  </Text>
                </View>
              )}
              <Text className="text-slate-500 font-bold mt-3 text-sm px-5">Term</Text>
              <View className="my-2 px-5">
                <TouchableOpacity
                  onPress={() => bottomSheetRef.current?.expand()}
                  className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full"
                >
                  <Text className="text-base text-main">{selectedCategory}</Text>
                </TouchableOpacity>
              </View>
            </>
          }
          renderItem={({ item, index }) => (
            <View className="px-5">
              {isLoadingState ? (
                <SkeletonClassCard />
              ) : (
                <ClassCard
                  name={item.name}
                  teacher={item.teacher}
                  corNumId={item.corNumId}
                  stuId={item.stuId}
                  section={item.section}
                  gbId={item.gbId}
                  t1={item.t1}
                  t2={item.t2}
                  s1={item.s1}
                  t3={item.t3}
                  t4={item.t4}
                  s2={item.s2}
                  term={selectedCategory}
                  courseData={item.courseData}
                />
              )}
            </View>
          )}
          keyExtractor={(item, index) => isLoadingState ? `skeleton-${index}` : `${item.name}-${index}`}
          ItemSeparatorComponent={() => <View className="h-[0.85rem]" />}
          ListEmptyComponent={
            <View className="flex-1 justify-center items-center py-12">
              {!isLoadingState && (
                <>
                  <Ionicons name="school-outline" size={64} color="#9ca3af" />
                  <Text className="text-center text-gray-500 mt-4 text-lg">
                    No courses found
                  </Text>
                  <Text className="text-center text-gray-400 mt-2">
                    Try selecting a different term
                  </Text>
                </>
              )}
            </View>
          }
          contentContainerStyle={{ paddingBottom: 32 }}
        />
      </View>
  );
}
