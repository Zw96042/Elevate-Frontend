import { Stack, useLocalSearchParams } from 'expo-router';
import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, ActivityIndicator, RefreshControl } from 'react-native';
import { useColorScheme } from 'nativewind';
import { colors } from '@/utils/colorTheme';
import { ScrollView } from 'react-native-gesture-handler';
import ClassCard2Sem from '@/components/ClassCard2Sem';
import { AcademicHistoryManager } from '@/lib/academicHistoryManager';
import { ensureUniqueCourseIds } from '@/utils/uniqueId';

interface CourseData {
  terms: string;
  finalGrade: string;
  sm1: string;
  sm2: string;
  pr1: string;
  pr2: string;
  pr3: string;
  pr4: string;
  pr5: string;
  pr6: string;
  pr7: string;
  pr8: string;
  rc1: string;
  rc2: string;
  rc3: string;
  rc4: string;
  ex1: string;
  ex2: string;
}

interface YearData {
  grade: number;
  courses: Record<string, CourseData>;
}

interface AcademicHistoryData {
  [year: string]: YearData;
  alt?: any;
}

const getGradeLevelName = (gradeNumber: number): string => {
  switch (gradeNumber) {
    case 9: return 'Freshman';
    case 10: return 'Sophomore';
    case 11: return 'Junior';
    case 12: return 'Senior';
    default: return `Grade ${gradeNumber}`;
  }
};

// Helper function to get course level
const getCourseLevel = (className: string): "AP" | "Honors" | "Regular" => {
  if (!className || typeof className !== 'string' || className.trim() === '') {
    return "Regular";
  }
  
  const normalized = className.toLowerCase().trim();
  
  // Roman numeral normalization
  const normalizeNumbers = (text: string): string => {
    const romanToNumber: { [key: string]: string } = {
      ' i': ' 1', ' ii': ' 2', ' iii': ' 3', ' iv': ' 4', ' v': ' 5', ' vi': ' 6'
    };
    const numberToRoman: { [key: string]: string } = {
      ' 1': ' i', ' 2': ' ii', ' 3': ' iii', ' 4': ' iv', ' 5': ' v', ' 6': ' vi'
    };
    
    let normalizedText = text;
    Object.entries(romanToNumber).forEach(([roman, number]) => {
      normalizedText = normalizedText.replace(new RegExp(roman, 'gi'), number);
    });
    Object.entries(numberToRoman).forEach(([number, roman]) => {
      normalizedText = normalizedText.replace(new RegExp(number, 'gi'), roman);
    });
    return normalizedText;
  };
  
  const apExceptions = ["multivariable calculus", "linear algebra", "stats 2: beyond ap statistics", "computer science 2", "computer science ii", "computer science 3", "computer science iii", "organic chemistry", "art historical methods"];
  const honorsExceptions = ["editorial leadership", "anatomy & physiology", "mentorship", "health science clinical", "robotics 2", "robotics ii", "robotics 3", "robotics iii", "swift coding", "business incubator", "engineering"];
  
  // First check for explicit AP pattern
  const hasAPKeyword = /\bap\b/.test(normalized);
  
  // Check AP exceptions with improved matching
  const isAPException = apExceptions.some(ex => {
    const normalizedCourse = normalizeNumbers(normalized);
    const normalizedEx = normalizeNumbers(ex);
    
    if (normalized === ex || normalizedCourse === normalizedEx) return true;
    if (ex.length > 10 && (normalized.includes(ex) || normalizedCourse.includes(normalizedEx))) return true;
    
    if (ex.length <= 10 && normalized.length > 5) {
      const courseWords = normalizedCourse.split(/\s+/);
      const exWords = normalizedEx.split(/\s+/);
      
      if (courseWords.length >= 2 && exWords.length >= 2) {
        const courseBase = courseWords.slice(0, -1).join(' ');
        const courseLevel = courseWords[courseWords.length - 1];
        const exBase = exWords.slice(0, -1).join(' ');
        const exLevel = exWords[exWords.length - 1];
        
        if (courseBase === exBase && courseLevel === exLevel) return true;
      } else {
        if (ex.includes(normalized) || normalizedEx.includes(normalizedCourse)) return true;
      }
    }
    
    return false;
  });
  
  if (hasAPKeyword || isAPException) return "AP";
  
  // Check for Honors pattern
  const hasHonorsKeyword = /\bhonors?\b/.test(normalized);
  
  // Check Honors exceptions with improved matching
  const isHonorsException = honorsExceptions.some(ex => {
    const normalizedCourse = normalizeNumbers(normalized);
    const normalizedEx = normalizeNumbers(ex);
    
    if (normalized === ex || normalizedCourse === normalizedEx) return true;
    if (ex.length > 10 && (normalized.includes(ex) || normalizedCourse.includes(normalizedEx))) return true;
    
    if (ex.length <= 10 && normalized.length > 5) {
      const courseWords = normalizedCourse.split(/\s+/);
      const exWords = normalizedEx.split(/\s+/);
      
      if (courseWords.length >= 2 && exWords.length >= 2) {
        const courseBase = courseWords[0];
        const courseLevel = courseWords[1];
        const exBase = exWords[0];
        const exLevel = exWords[1];
        
        if (courseBase === exBase && courseLevel === exLevel) return true;
      } else {
        if (ex.includes(normalized) || normalizedEx.includes(normalizedCourse)) return true;
      }
    }
    
    return false;
  });
  
  if (hasHonorsKeyword || isHonorsException) return "Honors";
  
  return "Regular";
};

const AcademicHistoryView = () => {
  const { gradeLevel, preloadedClasses } = useLocalSearchParams();
  const { colorScheme } = useColorScheme();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [academicData, setAcademicData] = useState<AcademicHistoryData | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Get grade level number from route parameter
  const gradeNumber = React.useMemo(() => {
    const gradeMap: Record<string, number> = {
      'Freshman': 9,
      'Sophomore': 10,
      'Junior': 11,
      'Senior': 12
    };
    return gradeMap[gradeLevel.toString()] || 9;
  }, [gradeLevel]);

  // Parse preloaded classes if they exist
  const preloadedCourses = React.useMemo(() => {
    if (preloadedClasses && typeof preloadedClasses === 'string') {
      try {
        const parsed = JSON.parse(preloadedClasses);
        return parsed;
      } catch (error) {
        console.error('Failed to parse preloaded classes:', error);
      }
    }
    return null;
  }, [preloadedClasses]);

  const loadAcademicHistory = useCallback(async (forceRefresh = false) => {
    try {
      setError(null);
      if (forceRefresh) setRefreshing(true);
      else setLoading(true);

      const { rawData: historyData } = await AcademicHistoryManager.getAcademicHistory(forceRefresh);
      setAcademicData(historyData);
    } catch (error) {
      console.error('Failed to load academic history:', error);
      setError(error instanceof Error ? error.message : 'Failed to load academic history');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    // If we have preloaded classes, don't show loading and don't try to load from API initially
    if (preloadedCourses && preloadedCourses.length > 0) {
      setLoading(false);
      return;
    }
    
    // Otherwise, load from academic history API
    loadAcademicHistory();
  }, [loadAcademicHistory, preloadedCourses]);

  const onRefresh = useCallback(() => {
    loadAcademicHistory(true);
  }, [loadAcademicHistory]);

  // Filter courses for the specific grade level
  const gradeData = React.useMemo(() => {
    if (!academicData) return null;
    
    // Find the year data that matches our target grade level
    const yearEntry = Object.entries(academicData).find(([year, data]) => {
      return year !== 'alt' && data.grade === gradeNumber;
    });
    
    return yearEntry ? yearEntry[1] : null;
  }, [academicData, gradeNumber]);

  const courses = React.useMemo(() => {
    let coursesArray: Array<{
      courseName: string;
      courseData: CourseData;
      savedLevel: string | null;
    }> = [];
    
    // First, try to use academic history data
    if (gradeData) {
      coursesArray = Object.entries(gradeData.courses)
        .filter(([courseName, courseData]) => {
          // Filter out courses with no meaningful data
          return courseData.finalGrade !== "P" && (
            courseData.sm1 || 
            courseData.sm2 || 
            courseData.finalGrade
          );
        })
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([courseName, courseData]) => ({
          courseName,
          courseData,
          savedLevel: null // No saved level for API data
        }));
    } 
    // If no academic history, use preloaded classes from AsyncStorage
    else if (preloadedCourses && Array.isArray(preloadedCourses)) {
      // Convert from our saved format to the expected format
      coursesArray = preloadedCourses.map(course => ({
        courseName: course.name,
        courseData: {
          terms: course.terms,
          finalGrade: course.grades.finalGrade,
          sm1: course.grades.sm1,
          sm2: course.grades.sm2,
          pr1: course.grades.pr1,
          pr2: course.grades.pr2,
          pr3: course.grades.pr3,
          pr4: course.grades.pr4,
          pr5: course.grades.pr5,
          pr6: course.grades.pr6,
          pr7: course.grades.pr7,
          pr8: course.grades.pr8,
          rc1: course.grades.rc1,
          rc2: course.grades.rc2,
          rc3: course.grades.rc3,
          rc4: course.grades.rc4,
          ex1: course.grades.ex1 || '',
          ex2: course.grades.ex2 || ''
        },
        savedLevel: course.level // Use saved level from AsyncStorage
      })).sort((a, b) => a.courseName.localeCompare(b.courseName));
    }
    
    // Ensure all courses have unique IDs
    return ensureUniqueCourseIds(coursesArray, gradeLevel.toString());
  }, [gradeData, preloadedCourses, gradeLevel]);

  if (loading && !refreshing) {
    return (
      <>
        <Stack.Screen
          options={{
            title: `${getGradeLevelName(gradeNumber)} Academic History`,
            headerStyle: { backgroundColor: '#2563eb' },
            headerTintColor: '#fff',
            headerTitleStyle: {
              fontWeight: 'bold',
              fontSize: 18,
            },
            headerBackTitle: 'GPA',
          }}
        />
        <View className="flex-1 bg-primary items-center justify-center">
          <ActivityIndicator size="large" color="#2563eb" />
          <Text className="text-accent mt-4">Loading academic history...</Text>
        </View>
      </>
    );
  }

  if (error) {
    return (
      <>
        <Stack.Screen
          options={{
            title: `${getGradeLevelName(gradeNumber)} Academic History`,
            headerStyle: { backgroundColor: '#2563eb' },
            headerTintColor: '#fff',
            headerTitleStyle: {
              fontWeight: 'bold',
              fontSize: 18,
            },
            headerBackTitle: 'GPA',
          }}
        />
        <ScrollView 
          className="flex-1 bg-primary"
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
          }
        >
          <View className="flex-1 items-center justify-center p-6">
            <Text className="text-red-500 text-lg font-semibold mb-2">Error Loading Data</Text>
            <Text className="text-accent text-center">{error}</Text>
          </View>
        </ScrollView>
      </>
    );
  }

  if (courses.length === 0) {
    return (
      <>
        <Stack.Screen
          options={{
            title: `${getGradeLevelName(gradeNumber)} Academic History`,
            headerStyle: { backgroundColor: '#2563eb' },
            headerTintColor: '#fff',
            headerTitleStyle: {
              fontWeight: 'bold',
              fontSize: 18,
            },
            headerBackTitle: 'GPA',
          }}
        />
        <ScrollView 
          className="flex-1 bg-primary"
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
          }
        >
          <View className="mx-6 mt-6">
            <View className="bg-cardColor rounded-2xl p-6 border border-dashed border-accent shadow-md">
              <Text className="text-main text-lg mb-3 text-center">
                No academic history found for {getGradeLevelName(gradeNumber)} year.
              </Text>
              <Text className="text-accent text-center">
                This could mean you haven't completed this grade level yet, or the data hasn't been updated in Skyward.
              </Text>
            </View>
          </View>
        </ScrollView>
      </>
    );
  }

  return (
    <>
      <Stack.Screen
        options={{
          title: `Academic History`,
          headerStyle: { backgroundColor: '#2563eb' },
          headerTintColor: '#fff',
          headerTitleStyle: {
            fontWeight: 'bold',
            fontSize: 18,
          },
          headerBackTitle: 'GPA',
        }}
      />
      <ScrollView 
        className="flex-1 bg-primary"
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
      >
        {/* Header Info */}
        <View className="mx-6 mt-6 mb-4">
          <View className="bg-cardColor rounded-2xl p-4 shadow-sm">
            <Text className="text-main text-xl font-semibold mb-2">
              {getGradeLevelName(gradeNumber)} Year Overview
            </Text>
            <View className="flex-row items-center justify-between">
              <Text className="text-accent">
                Total Courses: {courses.length}
              </Text>
            </View>
          </View>
        </View>
        {/* Course List */}
        

        {/* Course List */}
        {courses.map((course) => {
          const { courseName, courseData, savedLevel } = course;
          // Use saved level if available, otherwise calculate it
          const courseLevel = savedLevel || getCourseLevel(courseName);
          const sm1Grade = courseData.sm1 && courseData.sm1 !== "" && courseData.sm1 !== "P" && courseData.sm1 !== "X" 
            ? Number(courseData.sm1) 
            : -1;
          const sm2Grade = courseData.sm2 && courseData.sm2 !== "" && courseData.sm2 !== "P" && courseData.sm2 !== "X" 
            ? Number(courseData.sm2) 
            : -1;

          return (
            <ClassCard2Sem
              key={course.id}
              name={courseName}
              teacher=""
              s1={{ categories: { names: [], weights: [] }, total: sm1Grade }}
              s2={{ categories: { names: [], weights: [] }, total: sm2Grade }}
              term="SM1 Grade"
              gradeLevel={gradeLevel.toString()}
              courseLevel={courseLevel}
              showDeleteAction={false}
              termLabels={{ s1: "Fall", s2: "Spring" }}
            />
          );
        })}

        {/* Bottom spacing */}
        <View className="h-6" />
      </ScrollView>
    </>
  );
};

export default AcademicHistoryView;