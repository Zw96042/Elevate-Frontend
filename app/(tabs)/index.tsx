import React, { useCallback, useEffect, useState } from 'react';
import BottomSheet, { BottomSheetBackdrop, BottomSheetFlatList } from '@gorhom/bottom-sheet';
import { BottomSheetModalProvider } from '@gorhom/bottom-sheet';
import { useRef, useMemo } from 'react';
import { Modal, Pressable, View, Text, TouchableOpacity, FlatList } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Ionicons } from '@expo/vector-icons';
import ClassCard from '@/components/ClassCard';
import { Link as RouterLink, useFocusEffect } from 'expo-router';
import { SkywardAuth } from '@/lib/skywardAuthInfo';


const DATA = [
  // Your existing hardcoded course data...
  {
    name: 'BIOLOGY_1_HONORS',
    teacher: 'MARISA_SPEARS',
    t1: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 100,
    },
    t2: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 100,
    },
    s1: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [85, 95, 75] },
      total: 100,
    },
    t3: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 98,
    },
    t4: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 100,
    },
    s2: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 95,
    },
  },
  {
    name: 'AP_PRECALCULUS',
    teacher: 'KENZIE_SANCHEZ',
    t1: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 100,
    },
    t2: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 100,
    },
    s1: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 100,
    },
    t3: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 98,
    },
    t4: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 96,
    },
    s2: {
      categories: { names: ["Daily", "Labs", "Major"], grades: [90, 85, 99] },
      total: 95,
    },
  },
  // Add other course data similarly...
];

export default function Index() {
  const [hasCredentials, setHasCredentials] = useState(false);

  useFocusEffect(
    useCallback(() => {
      const checkCredentials = async () => {
        const result = await SkywardAuth.hasCredentials();
        setHasCredentials(result);
      };

      checkCredentials();
    }, [])
  );

  const [selectedCategory, setSelectedCategory] = useState<
    | 'Q1 Grades'
    | 'Q2 Grades'
    | 'SM1 Grade'
    | 'Q3 Grades'
    | 'Q4 Grades'
    | 'SM2 Grades'
  >('Q1 Grades');
  
  const bottomSheetRef = useRef<BottomSheet>(null);
  const snapPoints = useMemo(() => ['25%', '50%'], []);
  const terms: typeof selectedCategory[] = [
    'Q1 Grades',
    'Q2 Grades',
    'SM1 Grade',
    'Q3 Grades',
    'Q4 Grades',
    'SM2 Grades',
  ];

  return (
    <BottomSheetModalProvider>
      <View className="flex-1 bg-primary">
        <FlatList
          data={DATA}
          ListHeaderComponent={
            <>
              <View className="bg-blue-600 pt-14 pb-4 px-5">
                <Text className="text-white text-3xl font-bold">Courses</Text>
              </View>
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
          keyExtractor={(item) => item.name.toString()}
          ItemSeparatorComponent={() => <View className="h-4" />}
          ListEmptyComponent={
            <View className="mt-10 px-5">
              {hasCredentials ? (
                <Text className="text-center text-gray-500">No classes found.</Text>
              ) : (
                <Text className="text-center text-gray-500">
                  No credentials found.{' '}
                  <RouterLink href="/profile" className="text-blue-400 underline">
                    Go to Settings
                  </RouterLink>{' '}
                  to configure your account.
                </Text>
              )}
            </View>
          }
          contentContainerStyle={{ paddingBottom: 32 }}
        />

        <BottomSheet
          ref={bottomSheetRef}
          index={-1}
          snapPoints={['50%']}
          enablePanDownToClose={true}
          backgroundStyle={{ backgroundColor: '#1e293b' }}
          enableOverDrag={false}
          style={{ zIndex: 1 }}
          backdropComponent={(props) => (
          <BottomSheetBackdrop
            {...props}
            disappearsOnIndex={-1}
            appearsOnIndex={0}
          />
        )}
        >
          <BottomSheetFlatList
            data={terms}
            keyExtractor={(item) => item}
            renderItem={({ item }) => (
              <TouchableOpacity
                onPress={() => {
                  setSelectedCategory(item);
                  bottomSheetRef.current?.close();
                }}
                className="px-5 py-4"
              >
                <Text className="text-white text-lg">{item}</Text>
              </TouchableOpacity>
            )}
          />
        </BottomSheet>
      </View>
    </BottomSheetModalProvider>
  );
}