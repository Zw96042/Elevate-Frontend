import { Stack, useLocalSearchParams } from 'expo-router';
import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, ActivityIndicator, RefreshControl } from 'react-native';
import { useColorScheme } from 'nativewind';
import { colors } from '@/utils/colorTheme';
import { ScrollView } from 'react-native-gesture-handler';
import ClassCard2Sem from '@/components/ClassCard2Sem';
import { AcademicHistoryManager } from '@/lib/academicHistoryManager';

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
  const normalized = className.toLowerCase();
  
  const apExceptions = ["multivariable calculus", "linear algebra", "stats 2: beyond ap statistics", "computer science 2", "computer science 3", "organic chemistry", "art historical methods"];
  const honorsExceptions = ["editorial leadership", "anatomy & physiology", "mentorship", "health science clinical", "robotics", "swift coding", "business incubator", "engineering"];
  
  const isAP = /\bap\b/.test(normalized) || apExceptions.some(ex => normalized.includes(ex));
  if (isAP) return "AP";
  
  const isHonors = /\bhonors?\b/.test(normalized) || honorsExceptions.some(ex => normalized.includes(ex));
  if (isHonors) return "Honors";
  
  return "Regular";
};

const AcademicHistoryView = () => {
  const { gradeLevel } = useLocalSearchParams();
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
    loadAcademicHistory();
  }, [loadAcademicHistory]);

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
    if (!gradeData) return [];
    
    return Object.entries(gradeData.courses)
      .filter(([courseName, courseData]) => {
        // Filter out courses with no meaningful data
        return courseData.finalGrade !== "P" && (
          courseData.sm1 || 
          courseData.sm2 || 
          courseData.finalGrade
        );
      })
      .sort(([a], [b]) => a.localeCompare(b));
  }, [gradeData]);

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

  if (!gradeData || courses.length === 0) {
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
        {/* Header Info */}
        <View className="mx-6 mt-6 mb-4">
          <View className="bg-cardColor rounded-2xl p-4 border border-accent shadow-sm">
            <Text className="text-main text-xl font-semibold mb-2">
              {getGradeLevelName(gradeNumber)} Year Overview
            </Text>
            <View className="flex-row items-center justify-between">
              <Text className="text-accent">
                Total Courses: {courses.length}
              </Text>
              <Text className="text-accent text-sm">
                Pull to refresh
              </Text>
            </View>
          </View>
        </View>

        {/* Course List */}
        {courses.map(([courseName, courseData]) => {
          const courseLevel = getCourseLevel(courseName);
          const sm1Grade = courseData.sm1 && courseData.sm1 !== "" && courseData.sm1 !== "P" && courseData.sm1 !== "X" 
            ? Number(courseData.sm1) 
            : -1;
          const sm2Grade = courseData.sm2 && courseData.sm2 !== "" && courseData.sm2 !== "P" && courseData.sm2 !== "X" 
            ? Number(courseData.sm2) 
            : -1;

          return (
            <ClassCard2Sem
              key={courseName}
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