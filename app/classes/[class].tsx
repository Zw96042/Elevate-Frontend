import { View, Text, ScrollView, TouchableOpacity, FlatList, StyleSheet, Button, useColorScheme } from 'react-native'
import React, { useEffect, useMemo, useRef, useState, useCallback, useLayoutEffect } from 'react';
import { useFocusEffect } from '@react-navigation/native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import BottomSheet, { BottomSheetBackdrop, BottomSheetFlatList } from '@gorhom/bottom-sheet';
import { BottomSheetModalProvider } from '@gorhom/bottom-sheet';
import { Stack, useLocalSearchParams } from 'expo-router';
import { useNavigation } from '@react-navigation/native';
import formatClassName from '@/utils/formatClassName';
import { Ionicons } from '@expo/vector-icons';
import AssignmentCard from '@/components/AssignmentCard';
import { Switch } from 'react-native-gesture-handler';
import { parse } from '@babel/core';

export const ASSIN = [
    {
        className: "BIOLOGY_1_HONORS",
        name: "Pig Practical",
        term: "Q1",
        category: "Major",
        grade: 96,
        outOf: 100,
        dueDate: "05/09/25",
        artificial: false,
    },
    {
        className: "BIOLOGY_1_HONORS",
        name: "Pig Disection #1",
        term: "Q1",
        category: "Lab",
        grade: 95,
        outOf: 100,
        dueDate: "05/06/25",
        artificial: false,
    },
    {
        className: "BIOLOGY_1_HONORS",
        name: "Biodiv. Threats",
        term: "Q2",
        category: "Daily",
        grade: 100,
        outOf: 100,
        dueDate: "04/10/25",
        artificial: false,
    },
    {
        className: "AP_PRECALCULUS",
        name: "Test Intro to Trig",
        term: "SM1",
        category: "Major",
        grade: 89,
        outOf: 100,
        dueDate: "04/10/25",
        artificial: false,
    },
];

type TermLabel =
  | "Q1 Grades"
  | "Q2 Grades"
  | "SM1 Grade"
  | "Q3 Grades"
  | "Q4 Grades"
  | "SM2 Grades";

type Assignment = {
  className: string;
  name: string;
  term: string;
  category: string;
  grade: number;
  outOf: number;
  dueDate: string;
  artificial: boolean;
};

const ClassDetails = () => {
  const [isEnabled, setIsEnabled] = useState(false);

  const calculated = () => setIsEnabled(previous => !previous);

  const searchParams = useLocalSearchParams();

  const navigation = useNavigation();

  const term = searchParams.term as TermLabel;
  const classParam = searchParams.class;
  const className = Array.isArray(classParam) ? classParam[0] : classParam;

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
  const deleted = parseTermData(searchParams.deleted);
  
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

  const formattedName = formatClassName(className?.toString());
  

  const [dropdownOpen, setDropdownOpen] = React.useState(false);
  const bottomSheetRef = useRef<BottomSheet>(null);
  const snapPoints = useMemo(() => ['43%'], []);

  const [selectedCategory, setSelectedCategory] = React.useState<TermLabel>(term ?? "Q1 Grades");
  const [filteredAssignments, setFilteredAssignments] = useState<Assignment[]>(() => {
    if (!classParam || !selectedCategory) return [];
    return ASSIN.filter(
      item =>
        item.className === classParam &&
        item.term === selectedCategory.split(" ")[0] &&
        (!item.artificial || isEnabled)
    );
  });
  const [artificialAssignments, setArtificialAssignments] = useState<Assignment[]>([]);

  // Load artificial assignments for the current class from AsyncStorage and merge with real assignments
  const fetchArtificialAssignments = useCallback(async () => {
    if (!className) return;

    const data = await AsyncStorage.getItem('artificialAssignments');
    if (!data) {
      setArtificialAssignments([]);
      return;
    }

    const parsed = JSON.parse(data);
    const classAssignments = parsed[className] ?? [];
    setArtificialAssignments(classAssignments);

    const real = ASSIN.filter(
      item =>
        item.className === className &&
        item.term === selectedCategory.split(" ")[0]
    );

    const artificial = isEnabled
      ? classAssignments.filter(
          (item: Assignment) =>
            item.className === className &&
            item.term === selectedCategory.split(" ")[0]
        )
      : [];

    const artificialNames = new Set(artificial.map((a: any) => a.name));
    const filteredReal = real.filter(r => !artificialNames.has(r.name));

    setFilteredAssignments([...artificial, ...filteredReal]);
  }, [className, selectedCategory, isEnabled]);

  useEffect(() => {
    fetchArtificialAssignments();
  }, [fetchArtificialAssignments]);

  useFocusEffect(
    useCallback(() => {
      fetchArtificialAssignments();
    }, [fetchArtificialAssignments])
  );

  const addAssignment = async () => {
    const newAssignment = {
      className: className,
      name: "New Assignment",
      term: selectedCategory.split(" ")[0],
      category: "Daily",
      grade: 100,
      outOf: 100,
      dueDate: new Date().toISOString().slice(0, 10).replace(/-/g, "/").slice(5),
      artificial: true,
    };

    setArtificialAssignments(prev => [newAssignment, ...prev]);

    // Merge artificial and real assignments into filteredAssignments immediately
    const real = ASSIN.filter(
      item =>
        item.className === className &&
        item.term === selectedCategory.split(" ")[0]
    );

    const artificial = isEnabled
      ? [newAssignment, ...artificialAssignments]
      : [];

    const artificialNames = new Set(artificial.map(a => a.name));
    const filteredReal = real.filter(r => !artificialNames.has(r.name));

    setFilteredAssignments([...artificial, ...filteredReal]);

    // Save to AsyncStorage
    const existing = JSON.parse(await AsyncStorage.getItem("artificialAssignments") ?? "{}");

    const updated = {
      ...existing,
      [className]: [newAssignment, ...(existing[className] ?? [])],
    };

    await AsyncStorage.setItem("artificialAssignments", JSON.stringify(updated));
  };

  const currTerm = termMap[selectedCategory];

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        isEnabled ? (
          <TouchableOpacity onPress={addAssignment}>
            <Ionicons
              name="add-outline"
              size={24}
              color='white'
              style={{ marginRight: 15 }}
            />
          </TouchableOpacity>
        ) : null
      ),
    });
  }, [isEnabled, navigation]);
  
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
        }}
      />
        
          <View className='flex-row items-center'>
            <View className='px-5'>
              <View className='w-[3.5rem] h-[3.5rem] mt-6 rounded-full bg-highlight items-center justify-center'>
                  <Text className='text-highlightText font-bold text-sm'>{termMap[selectedCategory].total ?? "--"}%</Text>
              </View>
            </View>
            <View className='w-[80%]'>
              <View className="mt-6 pr-5 justify-center">
                <TouchableOpacity
                  onPress={() => bottomSheetRef.current?.expand()}
                  className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full"
                >
                  <Text className="text-base text-main">{selectedCategory}</Text>
                </TouchableOpacity>
              </View>
            </View>
          </View>
          <View className='flex-row mt-4 items-center px-5 justify-between'>
            <Text className='text-accent text-base font-medium'>Show Calculated</Text>
            <Switch
              value={isEnabled}
              onValueChange={setIsEnabled}
              className=''
            />
          </View>
          <View className="px-5 mt-4 space-y-2">
            <View className="flex-row justify-between mb-2">
              <Text className="text-highlightText font-bold text-base">Category</Text>
              <Text className="text-highlightText font-bold text-base">Percentage</Text>
            </View>
            <View className="h-[1px] bg-accent opacity-30 my-1" />
            {currTerm.categories.names.map((name, index) => (
              <View key={`row-${index}`}>
                <View className="flex-row justify-between items-center py-1">
                  <View className="rounded-md bg-highlight px-2">
                    <Text className="text-sm text-highlightText font-bold">{name}</Text>
                  </View>
                  <Text className="text-sm text-slate-400 font-bold">
                    {currTerm.categories.grades[index]?.toFixed(1) ?? '--'}%
                  </Text>
                </View>
                {index !== currTerm.categories.names.length - 1 && (
                  <View className="h-[1px] bg-accent opacity-30 my-1" />
                )}
              </View>
            ))}
            <View className="h-[1px] bg-accent opacity-30 my-1" />
          </View>
        <ScrollView className='mt-2'>
          <FlatList
            data={filteredAssignments}
            renderItem={({ item }: { item: Assignment }) => (
              <AssignmentCard 
                {...item}
                editing={isEnabled}
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
              renderItem={({ item }: { item: TermLabel }) => (
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