import React, { useCallback, useEffect, useState } from 'react';
import { View, Text, TouchableOpacity, FlatList, useColorScheme, LayoutAnimation, RefreshControl } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import ClassCard from '@/components/ClassCard';
import { useFocusEffect } from 'expo-router';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { useBottomSheet, BottomSheetProvider } from '@/context/BottomSheetContext'
import { useSettingSheet } from '@/context/SettingSheetContext';
import { loadReportCard } from '@/lib/loadReportCardHandler';
import * as Animatable from 'react-native-animatable';


// Default categories and weights (to be replaced by different API later)
const DEFAULT_CATEGORIES = {
  names: ["Daily", "Labs", "Major"],
  weights: [10, 30, 60],
};

// Transform API course data to component format
const transformCourseData = (apiCourses: any[]) => {
  return apiCourses.map(course => {
    // Create score map from API scores
    const scoreMap: { [key: string]: number } = {};
    course.scores?.forEach((score: any) => {
      const bucketKey = score.bucket?.toLowerCase();
      scoreMap[bucketKey] = score.score;
    });

    // Helper function to get score with API term mapping
    const getScore = (...keys: string[]) => {
      for (const key of keys) {
        if (scoreMap[key] !== undefined) {
          return scoreMap[key];
        }
      }
      return 0;
    };

    return {
      name: course.courseName?.toUpperCase().replace(/\s+/g, '_') || 'UNKNOWN_COURSE',
      teacher: course.instructor?.toUpperCase().replace(/\s+/g, '_') || 'UNKNOWN_INSTRUCTOR',
      t1: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('term 3', 'term3') // TERM 3 → RC1 (t1)
      },
      t2: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('term 6', 'term6') // TERM 6 → RC2 (t2) 
      },
      s1: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('sem 1', 'semester 1', 'semester1') // SEM 1 → SM1 (s1)
      },
      t3: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('term 9', 'term9') // TERM 9 → RC3 (t3)
      },
      t4: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('term 12', 'term12') // TERM 12 → RC4 (t4)
      },
      s2: {
        categories: DEFAULT_CATEGORIES,
        total: getScore('sem 2', 'semester 2', 'semester2') // SEM 2 → SM2 (s2)
      },
    };
  });
};


export default function Index() {
  const { bottomSheetRef, selectedCategory, setSelectedCategory } = useBottomSheet();
  const { settingSheetRef } = useSettingSheet();
  const [hasCredentials, setHasCredentials] = useState(false);
  const [coursesData, setCoursesData] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadCourses = async (isRefresh = false) => {
    try {
      if (isRefresh) {
        setRefreshing(true);
      } else {
        setLoading(true);
      }
      setError(null);
      
      const result = await loadReportCard();
      
      if (result.success && result.courses) {
        const transformedData = transformCourseData(result.courses);
        setCoursesData(transformedData);
      } else {
        setError(result.error || 'Failed to load courses');
        setCoursesData([]);
      }
    } catch (err: any) {
      console.error('Error loading courses:', err);
      setError(err.message || 'Failed to load courses');
      setCoursesData([]);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = useCallback(() => {
    if (hasCredentials) {
      loadCourses(true);
    }
  }, [hasCredentials]);

  useFocusEffect(
    useCallback(() => {
      const checkCredentials = async () => {
        const result = await SkywardAuth.hasCredentials();
        setHasCredentials(result);
        
        if (result) {
          await loadCourses();
        } else {
          setLoading(false);
        }
      };

      checkCredentials();
    }, [])
  );

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
          data={coursesData}
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
              ) : hasCredentials ? (
                <Text className="text-center text-gray-500">No classes found.</Text>
              ) : (
                <Text className="text-center text-gray-500">
                  No credentials found.{' '}
                  <Text
                    className="text-blue-400 underline"
                    onPress={() => settingSheetRef.current?.snapToIndex(0)}
                  >
                    Update the settings
                  </Text>{' '}
                  to configure your account.
                </Text>
              )}
            </View>
          }
          contentContainerStyle={{ paddingBottom: 32 }}
        />
      </View>
  );
}