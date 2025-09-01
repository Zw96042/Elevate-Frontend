import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, TouchableOpacity, FlatList, useColorScheme, LayoutAnimation, RefreshControl } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import ClassCard from '@/components/ClassCard';
import { useFocusEffect } from 'expo-router';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { useBottomSheet, BottomSheetProvider } from '@/context/BottomSheetContext'
import { useSettingSheet } from '@/context/SettingSheetContext';
import { UnifiedCourseData } from '@/lib/unifiedDataManager';
import { useUnifiedData } from '@/context/UnifiedDataContext';
import * as Animatable from 'react-native-animatable';


// Default categories and weights (to be replaced by different API later)
const DEFAULT_CATEGORIES = {
  names: ["Daily", "Labs", "Major"],
  weights: [10, 30, 60],
};

// Transform unified course data to component format
const transformCourseData = (unifiedCourses: UnifiedCourseData[]) => {
  return unifiedCourses.map(course => {
    // Create score map from current scores
    const scoreMap: { [key: string]: number } = {};
    course.currentScores?.forEach((score: any) => {
      const bucketKey = score.bucket?.toLowerCase();
      scoreMap[bucketKey] = score.score;
    });

    // Helper function to get score with fallback to historical data
    const getScore = (historicalKey: string, ...currentKeys: string[]) => {
      // First try current scores with multiple key variations
      for (const key of currentKeys) {
        if (scoreMap[key] !== undefined && scoreMap[key] !== null) {
          return scoreMap[key];
        }
      }
      
      // Fall back to historical grades
      const historicalValue = course.historicalGrades[historicalKey as keyof typeof course.historicalGrades];
      
      if (historicalValue && historicalValue !== '' && !isNaN(Number(historicalValue))) {
        return Number(historicalValue);
      }
      
      return "--";
    };

    return {
      name: course.courseName?.toUpperCase().replace(/\s+/g, '_') || 'UNKNOWN_COURSE',
      teacher: course.instructor?.toUpperCase().replace(/\s+/g, '_') || 'UNKNOWN_INSTRUCTOR',
      corNumId: course.courseId || '',
      stuId: course.stuId || '',
      section: course.section || '',
      gbId: course.gbId || '',
      period: course.period,
      semester: course.semester,
      t1: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('rc1', 'term 3', 'quarter 1', 'rc1')
      },
      t2: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('rc2', 'term 6', 'quarter 2', 'rc2')
      },
      s1: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('sm1', 'sem 1', 'semester 1', 'sm1')
      },
      t3: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('rc3', 'term 9', 'quarter 3', 'rc3')
      },
      t4: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('rc4', 'term 12', 'quarter 4', 'rc4')
      },
      s2: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('sm2', 'sem 2', 'semester 2', 'sm2')
      },
    };
  });
};

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
  const { currentGradeLevel } = require('@/hooks/useGradeLevel').useGradeLevel();
  const [filteredCourses, setFilteredCourses] = useState<any[]>([]);
  const [refreshing, setRefreshing] = useState(false);

  // No need for local loadCourses, use refreshCourses from context

  // Effect to filter courses when selectedCategory changes
  useEffect(() => {
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
      filteredRawCourses = coursesData.filter((c: any) => c.gradeYear === gradeYear);
    }
    const filtered = filterCoursesBySemester(transformCourseData(filteredRawCourses), selectedCategory);
    setFilteredCourses(filtered);
  }, [coursesData, selectedCategory]);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    refreshCourses(true).finally(() => setRefreshing(false));
  }, [refreshCourses]);

  useEffect(() => {
    if (!coursesData) {
      refreshCourses();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
          className='mb-[4rem]'
          data={filteredCourses}
          showsVerticalScrollIndicator={false}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
          }
          ListHeaderComponent={
            <>
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
          renderItem={({ item }) => (
            <View className="px-5">
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
              />
            </View>
          )}
          keyExtractor={(item, index) => `${item.name}-${index}`}
          ItemSeparatorComponent={() => <View className="h-4" />}
          ListEmptyComponent={
            <View className="mt-10 px-5">
              {loading ? (
                <Text className="text-center text-gray-500">Loading courses...</Text>
              ) : error ? (
                <Text className="text-center text-red-500">Error: {error}</Text>
              ) : (
                <Text className="text-center text-gray-500">No classes found.</Text>
              )}
            </View>
          }
          contentContainerStyle={{ paddingBottom: 32 }}
        />
      </View>
  );
}