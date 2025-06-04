import { View, Text, ScrollView, TouchableOpacity, FlatList, StyleSheet, Button } from 'react-native'
import React, { useCallback, useMemo, useRef } from 'react';
import { Link, useLocalSearchParams, useRouter } from 'expo-router'
import formatClassName from '@/utils/formatClassName';
import { Ionicons } from '@expo/vector-icons';
import AssignmentCard from '@/components/AssignmentCard';

const ASSIN = [
    {
        className: "BIOLOGY_1_HONORS",
        name: "Pig Practical",
        term: "Q1",
        category: "Major",
        grade: 96,
        outOf: 100,
        dueDate: "05/09/25"
    },
    {
        className: "BIOLOGY_1_HONORS",
        name: "Pig Disection #1",
        term: "Q1",
        category: "Lab",
        grade: 95,
        outOf: 100,
        dueDate: "05/06/25"
    },
    {
        className: "BIOLOGY_1_HONORS",
        name: "Biodiv. Threats",
        term: "Q2",
        category: "Daily",
        grade: 100,
        outOf: 100,
        dueDate: "04/10/25"
    },
    {
        className: "AP_PRECALCULUS",
        name: "Test Intro to Trig",
        term: "SM1",
        category: "Major",
        grade: 89,
        outOf: 100,
        dueDate: "04/10/25"
    },
];

const ClassDetails = () => {
  const router = useRouter();
  const { class: classParam } = useLocalSearchParams();
  const formattedName = formatClassName(classParam.toString());
  

  const [dropdownOpen, setDropdownOpen] = React.useState(false);
  const [selectedCategory, setSelectedCategory] = React.useState("Q1 Grades");
  const filteredAssignments = ASSIN.filter(item => item.className === classParam && item.term === selectedCategory.split(" ")[0]);
  return (
    <View className='bg-primary flex-1'>
        <View className="bg-blue-600">
            <View className='mt-14'>
                <TouchableOpacity onPress={() => router.back()} className='flex-row'>
                    <Ionicons name="chevron-back" size={24} color="white" />
                    <Text className='text-white text-xl font-medium'>Courses</Text>
                </TouchableOpacity>
            </View>
            <View className='pt-6 pb-4 px-5'>
                <Text className="text-white text-3xl font-bold">{formattedName}</Text>
                
            </View>
        </View>
        <ScrollView>
            <View className="mt-4 px-4 ">
              <TouchableOpacity
                onPress={() => setDropdownOpen(!dropdownOpen)}
                className="flex-row items-center justify-between bg-slate-800 px-4 py-3 rounded-full"
              >
                <Text className="text-base text-slate-300">{selectedCategory}</Text>
                <Ionicons name={dropdownOpen ? 'chevron-up' : 'chevron-down'} size={20} color="#cbd5e1"/>
              </TouchableOpacity>

              {dropdownOpen && (
                <View className="mt-2 bg-slate-800 rounded-xl">
                  {["Q1 Grades", "Q2 Grades", "SM1 Grade", "Q3 Grades", "Q4 Grades", "SM2 Grades"].map((label) => (
                    <TouchableOpacity
                      key={label}
                      onPress={() => {
                        setSelectedCategory(label);
                        setDropdownOpen(false);
                      }}
                      className="px-4 py-3"
                    >
                      <Text className="text-slate-300">{label}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              )}
            </View>
            <FlatList
            data={filteredAssignments}
            renderItem={({ item }) => (
            <AssignmentCard 
                {... item}
                />
            )}
            keyExtractor={(item) => item.name.toString()}
            className="mt-6 pb-32 px-3"
            scrollEnabled={false}
            ItemSeparatorComponent={() => <View className="h-4" />}
            ListEmptyComponent={
                <View className="mt-10 px-5">
                    <Text className="text-center text-gray-500">No assignments found</Text>
                </View>
            }
            />
        </ScrollView>  
    </View>
  )
}


export default ClassDetails