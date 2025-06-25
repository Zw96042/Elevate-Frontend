import { View, Text, ScrollView, TouchableOpacity, FlatList, StyleSheet, Button, useColorScheme } from 'react-native'
import React, { useMemo, useRef } from 'react';
import BottomSheet, { BottomSheetBackdrop, BottomSheetFlatList } from '@gorhom/bottom-sheet';
import { BottomSheetModalProvider } from '@gorhom/bottom-sheet';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router'
import formatClassName from '@/utils/formatClassName';
import { Ionicons } from '@expo/vector-icons';
import AssignmentCard from '@/components/AssignmentCard';

export const ASSIN = [
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

type TermLabel =
  | "Q1 Grades"
  | "Q2 Grades"
  | "SM1 Grade"
  | "Q3 Grades"
  | "Q4 Grades"
  | "SM2 Grades";

const ClassDetails = () => {
  const searchParams = useLocalSearchParams();

  const term = searchParams.term as TermLabel;
  const classParam = searchParams.class;

  const parseTermData = (param: string | string[] | undefined): TermData => {
    if (typeof param === "string") {
      try {
        return JSON.parse(param);
      } catch {
        return { categories: { names: [], grades: [] }, total: 0 };
      }
    }
    return { categories: { names: [], grades: [] }, total: 0 };
  };

  const t1 = parseTermData(searchParams.t1);
  const t2 = parseTermData(searchParams.t2);
  const s1 = parseTermData(searchParams.s1);
  const t3 = parseTermData(searchParams.t3);
  const t4 = parseTermData(searchParams.t4);
  const s2 = parseTermData(searchParams.s2);
  
  const termMap: Record<TermLabel, TermData> = {
        "Q1 Grades": t1,
        "Q2 Grades": t2,
        "SM1 Grade": s1,
        "Q3 Grades": t3,
        "Q4 Grades": t4,
        "SM2 Grades": s2,
    };

    type TermData = {
        categories: {
            names: string[];
            grades: number[];
        };
        total: number;
    };

  const formattedName = formatClassName(classParam.toString());
  

  const [dropdownOpen, setDropdownOpen] = React.useState(false);
  const bottomSheetRef = useRef<BottomSheet>(null);
  const snapPoints = useMemo(() => ['43%'], []);


  const [selectedCategory, setSelectedCategory] = React.useState<TermLabel>(term);
  const filteredAssignments = ASSIN.filter(item => item.className === classParam && item.term === selectedCategory.split(" ")[0]);

  const currTerm = termMap[selectedCategory];
  
  return (
    <View className='bg-primary flex-1'>
      <Stack.Screen
        options={{
          title: decodeURIComponent(formattedName || 'Class'),
          headerStyle: { backgroundColor: '#2563eb' },
          headerTintColor: '#fff',
          headerTitleStyle: {
            fontWeight: 'bold',
            fontSize: 18,
          },
          headerBackTitle: 'Classes',
          headerRight: () => (
            <TouchableOpacity>
              <Ionicons
                name="add-outline"
                size={24}
                color='white'
                style={{ marginRight: 15 }}
              />
            </TouchableOpacity>
          ),
        }}
      />
        <ScrollView>
            <Text className='text-slate-400 font-bold ml-5 mt-3 text-sm'>Term</Text>
            <View className="mt-2 px-5">
              <TouchableOpacity
                onPress={() => bottomSheetRef.current?.expand()}
                className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full"
              >
                <Text className="text-base text-main">{selectedCategory}</Text>
              </TouchableOpacity>
            </View>
            <View className='flex-row mt-4'>
              <View className='flex-1 items-center'>
                <Text className='text-highlightText font-bold text-sm'>Grade</Text>
                <View className='w-10 h-10 rounded-full bg-highlight items-center justify-center mt-2'>
                    <Text className='text-highlightText font-bold text-xs'>{termMap[selectedCategory].total ?? "--"}%</Text>
                </View>
              </View>
              <View className='flex-1 items-center'>
                <Text className='text-highlightText font-bold text-sm mb-2'>Category</Text>
                  <View>
                  {currTerm.categories.names
                  .map((item, index) => (
                    <View
                      key={`${item}-${index}`}
                      className="self-start rounded-md bg-highlight px-2"
                      style={{ marginBottom: index !== currTerm.categories.names.length - 1 ? 8 : 0 }}
                    >
                      <Text className="text-sm text-highlightText font-bold">{item}</Text>
                    </View>
                ))}
                </View>
              </View>
              <View className='flex-1 items-center'>
                <Text className='text-highlightText font-bold text-sm mb-2'>Real</Text>
                <View>
                  {currTerm.categories.grades
                    .map((item, index) => (
                      <Text 
                      key={`grade-${index}`} 
                      className="text-sm text-slate-400 font-bold"
                      style={{ marginBottom: index !== currTerm.categories.names.length - 1 ? 8 : 0 }}
                      >{item.toFixed(1)}%</Text>
                    ))}
                </View>
              </View>
              <View className='flex-1 items-center'>
                <Text className='text-highlightText font-bold text-sm mb-2'>Calculated</Text>
                <View>
                  {currTerm.categories.grades
                    .map((item, index) => (
                      <Text 
                      key={`grade-${index}`} 
                      className="text-sm text-slate-400 font-bold"
                      style={{ marginBottom: index !== currTerm.categories.names.length - 1 ? 8 : 0 }}
                      >{item.toFixed(1)}%</Text>
                    ))}
                </View>
              </View>
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
        <BottomSheetModalProvider>
          <BottomSheet
            ref={bottomSheetRef}
            index={-1}
            snapPoints={['47%']}
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
              data={["Q1 Grades", "Q2 Grades", "SM1 Grade", "Q3 Grades", "Q4 Grades", "SM2 Grades"] as TermLabel[]}
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
              scrollEnabled={false}
            />
          </BottomSheet>
        </BottomSheetModalProvider>
    </View>
  )
}


export default ClassDetails