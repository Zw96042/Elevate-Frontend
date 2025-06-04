import { View, Text, FlatList } from 'react-native';
import React from 'react';
import { ASSIN } from '../classes/[class]';
import AssignmentDateCard from '@/components/AssignmentDateCard';
import formatClassName from '@/utils/formatClassName';

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
  return (
    <View className="flex-1 bg-primary">
      <View className="bg-blue-600 pt-14 pb-4 px-5">
        <Text className="text-white text-3xl font-bold">Assignments</Text>
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
              <Text className="text-slate-400 font-bold text-lg px-5 mt-4">
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
        
      />
    </View>
  );
};

export default assignments;