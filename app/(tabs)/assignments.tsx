import { View, Text, FlatList, TouchableOpacity } from 'react-native';
import React, { useCallback, useState } from 'react';
import { ASSIN } from '../classes/[class]';
import AssignmentDateCard from '@/components/AssignmentDateCard';
import formatClassName from '@/utils/formatClassName';
import { Ionicons } from '@expo/vector-icons';
import { useSettingSheet } from '@/context/SettingSheetContext';
import { useFocusEffect } from 'expo-router';
import { SkywardAuth } from '@/lib/skywardAuthInfo';

type Assignment = {
  className: string;
  name: string;
  term: string;
  category: string;
  grade: number;
  outOf: number;
  dueDate: string;
};

type ListItem =
  | { type: 'header'; date: string }
  | { type: 'item'; assignment: Assignment };

// Step 1: Group assignments by due date
const groupedAssignments = ASSIN.reduce((acc, assignment) => {
  if (!acc[assignment.dueDate]) {
    acc[assignment.dueDate] = [];
  }
  acc[assignment.dueDate].push(assignment);
  return acc;
}, {} as Record<string, typeof ASSIN>);

// Step 2: Sort due dates from most recent to oldest
const sortedDates = Object.keys(groupedAssignments).sort(
  (a, b) => new Date(b).getTime() - new Date(a).getTime()
);

// Step 3: Flatten data for FlatList
const listData: ListItem[] = sortedDates.flatMap(date => [
  { type: 'header', date },
  ...groupedAssignments[date].map(assignment => ({ type: "item" as const, assignment }))
]);

const assignments = () => {
  const { settingSheetRef } = useSettingSheet();

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

  return (
    <View className="flex-1 bg-primary">
      <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
        <Text className="text-white text-3xl font-bold">Assignments</Text>
        <TouchableOpacity
            onPress={() => settingSheetRef.current?.snapToIndex(1)}
          >
          <Ionicons name='cog-outline' color={'#fff'} size={26} />
        </TouchableOpacity>
      </View>

      <FlatList
        data={listData}
        keyExtractor={(item, index) =>
          item.type === 'header'
            ? `header-${item.date}`
            : `item-${index}-${item.assignment.name}`
        }
        className='px-5'
        renderItem={({ item, index }) => {
          if (item.type === 'header') {
            return (
              <Text className="text-accent font-bold text-lg mt-4">
                {item.date}
              </Text>
            );
          }
          {/* className, name, category, grade, outOf, dueDate */}
          const a = item.assignment;
          return (
            <View style={{ marginBottom: index < listData.length - 1 && listData[index + 1].type === 'item' ? 16 : 0 }}>
              <AssignmentDateCard 
                className={formatClassName(a.className)}
                name={a.name}
                category={a.category}
                grade={a.grade}
                outOf={a.outOf}
                dueDate={a.dueDate}
              />
            </View>
          );
          
        }}
        ListEmptyComponent={
          <Text className="text-center text-gray-500 mt-10">
            {hasCredentials ? (
              'No messages found.'
            ) : (
              <Text className="text-center text-gray-500">
                No credentials found.{' '}
                <Text
                  className="text-blue-400 underline"
                  onPress={() => settingSheetRef.current?.snapToIndex(1)}
                >
                  Update the settings
                </Text>{' '}
                to configure your account.
              </Text>
            )}
          </Text>
        }
        
      />
    </View>
  );
};

export default assignments;