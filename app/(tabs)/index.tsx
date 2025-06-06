import React, { useEffect, useState } from 'react';
import { View, Text, TouchableOpacity, FlatList, ScrollView } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Ionicons } from '@expo/vector-icons';
import ClassCard from '@/components/ClassCard';
import { Link as RouterLink } from 'expo-router';
import { authenticate } from '@/lib/authHandler';


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
  const [credentialsSet, setCredentialsSet] = useState<boolean | null>(null);
  const [authenticating, setAuthenticating] = useState(false);
  const [selectedCategory, setSelectedCategory] = useState<
    | 'Q1 Grades'
    | 'Q2 Grades'
    | 'SM1 Grade'
    | 'Q3 Grades'
    | 'Q4 Grades'
    | 'SM2 Grades'
  >('Q1 Grades');
  const [dropdownOpen, setDropdownOpen] = useState(false);

  useEffect(() => {
    const runAuth = async () => {
      setAuthenticating(true);
      const result = await authenticate();

      if (result.success) {
        setCredentialsSet(true);
      } else {
        console.error('Authentication failed:', result.error);
        setCredentialsSet(false);
      }

      setAuthenticating(false);
    };

    runAuth();
  }, []);

  const terms: typeof selectedCategory[] = [
    'Q1 Grades',
    'Q2 Grades',
    'SM1 Grade',
    'Q3 Grades',
    'Q4 Grades',
    'SM2 Grades',
  ];

  return (
    <View className="flex-1 bg-primary">
      <View className="bg-blue-600 pt-14 pb-4 px-5">
        <Text className="text-white text-3xl font-bold">Courses</Text>
      </View>

      <ScrollView
        className="flex-1 px-5"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ minHeight: '100%', paddingBottom: 10 }}
      >
        {authenticating && (
          <Text className="text-center text-gray-500 mt-3">Authenticating...</Text>
        )}

        <Text className="text-slate-400 font-bold mt-3 text-sm">Term</Text>

        <View className="my-2 px-0">
          <TouchableOpacity
            onPress={() => setDropdownOpen(!dropdownOpen)}
            className="flex-row items-center justify-between bg-slate-800 px-4 py-3 rounded-full"
          >
            <Text className="text-base text-slate-300">{selectedCategory}</Text>
            <Ionicons
              name={dropdownOpen ? 'chevron-up' : 'chevron-down'}
              size={20}
              color="#cbd5e1"
            />
          </TouchableOpacity>

          {dropdownOpen && (
            <View className="mt-2 bg-slate-800 rounded-xl">
              {terms.map((term) => (
                <TouchableOpacity
                  key={term}
                  onPress={() => {
                    setSelectedCategory(term);
                    setDropdownOpen(false);
                  }}
                  className="px-4 py-3"
                >
                  <Text className="text-slate-300">{term}</Text>
                </TouchableOpacity>
              ))}
            </View>
          )}
        </View>

        <View className="flex-1 mt-0">
          <FlatList
            data={DATA}
            renderItem={({ item }) => (
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
            )}
            keyExtractor={(item) => item.name.toString()}
            className="mt-2 pb-32"
            scrollEnabled={false}
            ItemSeparatorComponent={() => <View className="h-4" />}
            ListEmptyComponent={
              <View className="mt-10 px-5">
                {credentialsSet === null ? (
                  <Text className="text-center text-gray-500">Checking credentials...</Text>
                ) : credentialsSet ? (
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
          />
        </View>
      </ScrollView>
    </View>
  );
}