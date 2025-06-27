import { View, Text, ScrollView, TouchableOpacity, FlatList, StyleSheet, Button, useColorScheme, Keyboard } from 'react-native'
import React, { useEffect, useMemo, useRef, useState, useCallback, useLayoutEffect } from 'react';
import { useFocusEffect } from '@react-navigation/native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import BottomSheet, { BottomSheetBackdrop, BottomSheetFlatList, BottomSheetView, TouchableWithoutFeedback } from '@gorhom/bottom-sheet';
import { BottomSheetModalProvider } from '@gorhom/bottom-sheet';
import { Stack, useLocalSearchParams } from 'expo-router';
import { useNavigation } from '@react-navigation/native';
import formatClassName from '@/utils/formatClassName';
import { calculateGradeSummary } from '@/utils/calculateGrades';
import { Ionicons } from '@expo/vector-icons';
import AssignmentCard from '@/components/AssignmentCard';
import { Switch, TextInput } from 'react-native-gesture-handler';
import { parse } from '@babel/core';
import { colors } from '@/utils/colorTheme';
import { useSettingSheet } from '@/context/SettingSheetContext';
import { useBottomSheet, BottomSheetProvider } from '@/context/BottomSheetContext'

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
        category: "Labs",
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
        return { categories: { names: [], weights: [] }, total: 0 };
      }
    }
    return { categories: { names: [], weights: [] }, total: 0 };
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
            weights: number[];
        };
        total: number;
    };

  const formattedName = formatClassName(className?.toString());
  

  const addSheetRef = useRef<BottomSheet>(null);

  const { bottomSheetRef, selectedCategory, setSelectedCategory } = useBottomSheet();
  const [filteredAssignments, setFilteredAssignments] = useState<Assignment[]>(() => {
    if (!classParam || !selectedCategory) return [];
    return ASSIN.filter(
      item =>
        item.className === classParam &&
        item.term === selectedCategory.split(" ")[0] &&
        (!item.artificial || isEnabled)
    );
  });
  const [courseSummary, setCourseSummary] = useState<{
    courseTotal: number;
    categories: Record<string, {
      average: number;
      weight: number;
      rawPoints: number;
      rawTotal: number;
    }>;
  }>({ courseTotal: 0, categories: {} });
  const [artificialAssignments, setArtificialAssignments] = useState<Assignment[]>([]);

  // Make sure currTerm is declared before use in fetchArtificialAssignments dependencies
  const currTerm = termMap[selectedCategory];
  // Load artificial assignments for the current class from AsyncStorage and merge with real assignments
  const fetchArtificialAssignments = useCallback(async () => {
    if (!className) return;

    const data = await AsyncStorage.getItem('artificialAssignments');
    if (!data) {
      setArtificialAssignments([]);
      setFilteredAssignments([]);
      setCourseSummary({ courseTotal: 0, categories: {} });
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
    // Compute grade summary and update courseSummary state
    const all = [...artificial, ...filteredReal];
    const weightsMap = Object.fromEntries(
      currTerm.categories.names.map((name, i) => [name, currTerm.categories.weights[i]])
    );
    // Adjustment logic: skip categories with no assignments, normalize weights to sum to 100%
    const originalWeights = weightsMap;
    const nonEmptyCategories = all.reduce((set, a) => {
      if (!set.has(a.category)) set.add(a.category);
      return set;
    }, new Set<string>());

    const adjustedWeights = Object.entries(originalWeights)
      .filter(([name]) => nonEmptyCategories.has(name));

    const totalAdjustedWeight = adjustedWeights.reduce((sum, [, w]) => sum + w, 0);

    const normalizedWeights = Object.fromEntries(
      adjustedWeights.map(([name, weight]) => [name, (weight / totalAdjustedWeight) * 100])
    );

    setCourseSummary(calculateGradeSummary(all, normalizedWeights));
  }, [className, selectedCategory, isEnabled, currTerm.categories.names, currTerm.categories.weights]);

  useEffect(() => {
    fetchArtificialAssignments();
  }, [fetchArtificialAssignments]);

  useFocusEffect(
    useCallback(() => {
      fetchArtificialAssignments();
    }, [fetchArtificialAssignments])
  );

  // console.log(currTerm.categories);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        isEnabled ? (
          <TouchableOpacity onPress={() => addSheetRef.current?.expand()}>
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

  const colorScheme = useColorScheme()
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light;

  const [sheetIndex, setSheetIndex] = useState(-1);

  // New assignment state for assignment creation form
  const [newAssignment, setNewAssignment] = useState({
    name: '',
    category: '',
    grade: '',
    outOf: '',
  });

  
  useEffect(() => {
      const showSub = Keyboard.addListener('keyboardDidShow', () => {
        if (sheetIndex !== -1) {
          addSheetRef.current?.snapToPosition('100%', { duration: 150 });
        }
      });
  
      const hideSub = Keyboard.addListener('keyboardDidHide', () => {
        if (sheetIndex !== -1) {
          addSheetRef.current?.snapToPosition('60%', { duration: 150 });
        }
      });
  
      return () => {
        showSub.remove();
        hideSub.remove();
      };
    }, [sheetIndex]);

  const handleSheetChanges = (index: number) => {
    setSheetIndex(index);
  };
  
  
  return (
    <TouchableWithoutFeedback onPress={Keyboard.dismiss} accessible={false}>
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
                  <Text className='text-highlightText font-bold text-sm'>
                    {courseSummary.courseTotal?.toFixed(1) ?? "--"}%
                  </Text>
                </View>
              </View>
              <View className='w-[80%]'>
                <View className="mt-6 pr-5 justify-center">
                  <TouchableOpacity
                    onPress={() => bottomSheetRef.current?.snapToIndex(1)}
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
                <Text className="text-highlightText font-bold text-base">Weight</Text>
              </View>
              <View className="h-[1px] bg-accent opacity-30 my-1" />
              {currTerm.categories.names.map((name, index) => (
                <View key={`row-${index}`}>
                  <View className="py-1">
                    <View className="flex-row justify-between items-center">
                      <View className="rounded-md bg-highlight px-2">
                        <Text className="text-sm text-highlightText font-bold">{name}</Text>
                      </View>
                      <Text className="text-sm text-slate-400 font-bold">
                        Avg: {(courseSummary?.categories[name]?.average?.toFixed(1) ?? '--')}%
                        {' • '}
                        Weight: {(currTerm.categories.weights[index] ?? 0).toFixed(1)}%
                        {courseSummary.categories[name]
                          ? courseSummary.categories[name].weight.toFixed(1) !== (currTerm.categories.weights[index] ?? 0).toFixed(1)
                            ? ` → ${courseSummary.categories[name].weight.toFixed(1)}%`
                            : ''
                          : ' → 0%'}
                      </Text>
                    </View>
                    {courseSummary.categories[name] && (
                      <View className="h-2 w-full bg-accent rounded-full overflow-hidden mt-1">
                        <View
                          className="bg-highlight h-2"
                          style={{ width: `${courseSummary.categories[name].average}%` }}
                        />
                      </View>
                    )}
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
          <BottomSheet
              ref={addSheetRef}
              index={-1}
              snapPoints={["42%"]}
              backgroundStyle={{ backgroundColor: cardColor }}
              overDragResistanceFactor={1}
              enablePanDownToClose={true}
              keyboardBehavior={'extend'}
              onChange={handleSheetChanges}
              backdropComponent={(props) => (
                <BottomSheetBackdrop
                  {...props}
                  disappearsOnIndex={-1}
                  appearsOnIndex={0}
                />
              )}
            >
              <BottomSheetView className="bg-cardColor p-4">
                <Text className="text-xl text-main font-bold mb-4">Add New Assignment</Text>

                <View className="mb-5">
                  <Text className="text-sm font-semibold text-main mb-1">Assignment Name</Text>
                  <TextInput
                    className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                    placeholder="Enter name"
                    value={newAssignment.name}
                    onChangeText={(text) => setNewAssignment((prev) => ({ ...prev, name: text }))}
                  />
                </View>

                <View className="mb-5">
                  <Text className="text-sm font-semibold text-main mb-1">Category</Text>
                  <View className="flex-row flex-wrap gap-2">
                    {currTerm.categories.names.map((category) => (
                      <TouchableOpacity
                        key={category}
                        onPress={() => setNewAssignment((prev) => ({ ...prev, category }))}
                        className={`px-3 py-1 rounded-full border ${
                          newAssignment.category === category
                            ? 'bg-highlight border-highlight'
                            : 'border-accent'
                        }`}
                      >
                        <Text
                          className={`text-sm ${
                            newAssignment.category === category
                              ? 'text-highlightText font-bold'
                              : 'text-main'
                          }`}
                        >
                          {category}
                        </Text>
                      </TouchableOpacity>
                    ))}
                  </View>
                </View>

                <View className="h-[1px] bg-accent opacity-20 mb-5" />

                <View className="mb-5">
                  <Text className="text-sm font-semibold text-main mb-1">Grade</Text>
                  <TextInput
                    className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                    placeholder="Enter grade"
                    keyboardType="numeric"
                    value={newAssignment.grade}
                    onChangeText={(text) => setNewAssignment((prev) => ({ ...prev, grade: text }))}
                  />
                </View>

                <View className="mb-6">
                  <Text className="text-sm font-semibold text-main mb-1">Out Of</Text>
                  <TextInput
                    className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                    placeholder="Enter total"
                    keyboardType="numeric"
                    value={newAssignment.outOf}
                    onChangeText={(text) => setNewAssignment((prev) => ({ ...prev, outOf: text }))}
                  />
                </View>

                <TouchableOpacity
                  className="bg-highlight rounded-md py-3 items-center"
                  onPress={async () => {
                    const assignment = {
                      className,
                      name: newAssignment.name,
                      term: selectedCategory.split(" ")[0],
                      category: newAssignment.category,
                      grade: parseFloat(newAssignment.grade),
                      outOf: parseFloat(newAssignment.outOf),
                      dueDate: new Date().toISOString().slice(0, 10).replace(/-/g, "/").slice(5),
                      artificial: true,
                    };

                    const updatedArtificial = [assignment, ...artificialAssignments];
                    setArtificialAssignments(updatedArtificial);

                    const real = ASSIN.filter(
                      item =>
                        item.className === className &&
                        item.term === selectedCategory.split(" ")[0]
                    );

                    const artificial = isEnabled
                      ? updatedArtificial.filter(
                          a =>
                            a.className === className &&
                            a.term === selectedCategory.split(" ")[0]
                        )
                      : [];

                    const artificialNames = new Set(artificial.map(a => a.name));
                    const filteredReal = real.filter(r => !artificialNames.has(r.name));

                    setFilteredAssignments([...artificial, ...filteredReal]);

                    const existing = JSON.parse(await AsyncStorage.getItem("artificialAssignments") ?? "{}");

                    const updated = {
                      ...existing,
                      [className]: updatedArtificial,
                    };

                    await AsyncStorage.setItem("artificialAssignments", JSON.stringify(updated));
                    addSheetRef.current?.close();
                    setNewAssignment({ name: '', category: '', grade: '', outOf: '' });
                  }}
                >
                  <Text className="text-highlightText font-bold">Add Assignment</Text>
                </TouchableOpacity>
              </BottomSheetView>
            </BottomSheet>
      </View>
    </TouchableWithoutFeedback>
  )
}


export default ClassDetails