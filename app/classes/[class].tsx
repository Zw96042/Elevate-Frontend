import {
  View,
  Text,
  TouchableOpacity,
  FlatList,
  Keyboard,
  TouchableWithoutFeedback,
  Switch,
  useColorScheme,
} from "react-native";
import Animated, {
  useSharedValue,
  useAnimatedReaction,
  withTiming,
  runOnJS,
  Easing,
  useAnimatedStyle,
} from 'react-native-reanimated';
import React, {
  useEffect,
  useState,
  useCallback,
  useLayoutEffect,
  useRef,
} from "react";
import { useFocusEffect, useNavigation } from "@react-navigation/native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { Stack, useLocalSearchParams } from "expo-router";
import formatClassName from "@/utils/formatClassName";
import { calculateGradeSummary } from "@/utils/calculateGrades";
import { ensureUniqueAssignmentIds } from "@/utils/uniqueId";
import { Ionicons } from "@expo/vector-icons";
import AssignmentCard from "@/components/AssignmentCard";
import { useAddAssignmentSheet } from "@/context/AddAssignmentSheetContext";
import { useBottomSheet } from "@/context/BottomSheetContext";
import PieChart from "react-native-pie-chart";
import { MotiView, AnimatePresence } from 'moti'
import { fetchGradeInfo } from '@/lib/gradeInfoClient';
import { ScrollView } from "react-native-gesture-handler";




const bucketMap: Record<TermLabel, string> = {
  "Q1 Grades": "TERM 3",
  "Q2 Grades": "TERM 6",
  "SM1 Grade": "SEM 1",
  "Q3 Grades": "TERM 9",
  "Q4 Grades": "TERM 12",
  "SM2 Grades": "SEM 2",
};

// Helper function to get relevant terms for a selected category
const getRelevantTerms = (selectedCategory: TermLabel): string[] => {
  switch (selectedCategory) {
    case "SM1 Grade":
      return ["Q1", "Q2"]; // RC1 + RC2
    case "SM2 Grades":
      return ["Q3", "Q4"]; // RC3 + RC4
    default:
      return [selectedCategory.split(" ")[0]]; // Single term
  }
};

type TermLabel =
  | "Q1 Grades"
  | "Q2 Grades"
  | "SM1 Grade"
  | "Q3 Grades"
  | "Q4 Grades"
  | "SM2 Grades";

type Assignment = {
  id?: string;
  className: string;
  name: string;
  term: string;
  category: string;
  grade: string;
  outOf: number;
  dueDate: string;
  artificial: boolean;
};

type TermData = {
  categories: {
    names: string[];
    weights: number[];
  };
  total: number | string; // Allow both number and string (for "--")
};

const ClassDetails = () => {
  const [isEnabled, setIsEnabled] = useState<boolean | null>(null);
  const [displayGrade, setDisplayGrade] = useState(0);
  const animatedGrade = useSharedValue(0);

  const searchParams = useLocalSearchParams();
  const navigation = useNavigation();

  const classParam = searchParams.class;
  const className = Array.isArray(classParam) ? classParam[0] : classParam;
  const classIdParam = searchParams.classId;
  const classId = Array.isArray(classIdParam) ? classIdParam[0] : classIdParam;
  const corNumId = Array.isArray(searchParams.corNumId) ? searchParams.corNumId[0] : searchParams.corNumId;
  const stuId = Array.isArray(searchParams.stuId) ? searchParams.stuId[0] : searchParams.stuId;
  const section = Array.isArray(searchParams.section) ? searchParams.section[0] : searchParams.section;
  const gbId = Array.isArray(searchParams.gbId) ? searchParams.gbId[0] : searchParams.gbId;



  const parseTermData = (param: string | string[] | undefined): TermData => {
    if (typeof param === "string") {
      try {
        return JSON.parse(param);
      } catch {
        return { categories: { names: [], weights: [] }, total: "--" };
      }
    }
    return { categories: { names: [], weights: [] }, total: "--" };
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

  const formattedName = formatClassName(className?.toString());

  const { bottomSheetRef, selectedCategory, setSelectedCategory } = useBottomSheet();
  const [filteredAssignments, setFilteredAssignments] = useState<Assignment[]>([]);
  const [courseSummary, setCourseSummary] = useState<{
    courseTotal: string;
    categories: Record<
      string,
      {
        average: number;
        weight: number;
        rawPoints: number;
        rawTotal: number;
      }
    >;
  }>({ courseTotal: "*", categories: {} });
  const [artificialAssignments, setArtificialAssignments] = useState<Assignment[]>([]);

  const currTerm = termMap[selectedCategory];
  // Use API categories for current term, fallback to termMap if API fails
  const [apiCategories, setApiCategories] = useState<{ names: string[]; weights: number[] }>({ names: [], weights: [] });
  // ...existing code...


  // Store API assignments and categories in state
  const [apiAssignments, setApiAssignments] = useState<Assignment[]>([]);

  // Fetch assignments and categories from API only when identifiers change
  const fetchApiAssignments = useCallback(async () => {
    if (!className || !stuId || !corNumId || !section || !gbId || !selectedCategory) return;
    const bucket = bucketMap[selectedCategory as TermLabel];
    try {
      const result = await fetchGradeInfo({ stuId, corNumId, section, gbId, bucket });
      const backendData = result?.data?.data;
      const assignments = backendData?.gradebook?.flatMap((cat: any) =>
        (cat.assignments ?? []).map((a: any, index: number) => ({
          id: `${cat.category}-${index}-${a.name}`,
          className: className,
          name: a.name,
          term: selectedCategory.split(" ")[0],
          category: cat.category,
          grade: a.points?.earned ?? "*",
          outOf: a.points?.total ?? 100,
          dueDate: a.date ?? "",
          artificial: false,
        }))
      ) ?? [];
      setApiAssignments(assignments);
      const categories = {
        names: backendData?.gradebook?.map((cat: any) => cat.category) ?? [],
        weights: backendData?.gradebook?.map((cat: any) => cat.weight) ?? []
      };
      setApiCategories(categories);
      // console.log(categories);
    } catch (err) {
      setApiAssignments([]);
      setApiCategories({ names: [], weights: [] });
    }
  }, [className, classId, selectedCategory, stuId, corNumId, section, gbId]);

  // Mesh artificial assignments with API assignments
  const meshAssignments = useCallback(async () => {
    const data = await AsyncStorage.getItem("artificialAssignments");
    if (!data) {
      const realWithIds = ensureUniqueAssignmentIds(apiAssignments);
      setArtificialAssignments([]);
      setFilteredAssignments(realWithIds);
      // Calculate summary
      const all = realWithIds.filter(a => a.grade !== '*');
      const weightsMap = Object.fromEntries(
        (apiCategories.names || []).map((name, i) => [name, apiCategories.weights[i]])
      );
      const nonEmptyCategories = all.reduce((set, a) => {
        if (!set.has(a.category)) set.add(a.category);
        return set;
      }, new Set<string>());
      const adjustedWeights = Object.entries(weightsMap).filter(([name]) =>
        nonEmptyCategories.has(name)
      );
      const totalAdjustedWeight = adjustedWeights.reduce((sum, [, w]) => sum + w, 0);
      const normalizedWeights = Object.fromEntries(
        adjustedWeights.map(([name, weight]) => [name, (weight / totalAdjustedWeight) * 100])
      );
      setCourseSummary(calculateGradeSummary(all, normalizedWeights));
      return;
    }
    const parsed = JSON.parse(data);
    // Get relevant terms for the current selected category
    const relevantTerms = getRelevantTerms(selectedCategory);
    
    // Collect artificial assignments from all relevant term storage keys
    let allArtificialAssignments: Assignment[] = [];
    
    // For SM1/SM2, also check for assignments stored directly with the semester term
    const termsToCheck = [...relevantTerms];
    if (selectedCategory === "SM1 Grade" || selectedCategory === "SM2 Grades") {
      termsToCheck.push(selectedCategory.split(" ")[0]); // Add "SM1" or "SM2"
    }
    
    termsToCheck.forEach(term => {
      const storageKey = `${className}_${corNumId}_${section}_${gbId}_${term}`;
      const classAssignments = parsed[storageKey] ?? [];
      allArtificialAssignments = [...allArtificialAssignments, ...classAssignments];
      
      // For individual terms, also check the old format (full term name)
      if (term === selectedCategory.split(" ")[0]) {
        const oldStorageKey = `${className}_${corNumId}_${section}_${gbId}_${selectedCategory}`;
        const oldAssignments = parsed[oldStorageKey] ?? [];
        allArtificialAssignments = [...allArtificialAssignments, ...oldAssignments];
      }
    });
    
    // Only use assignments from the relevant terms
    const artificial = isEnabled ? allArtificialAssignments : [];

    // Ensure artificial assignments have grade and outOf, do NOT mutate in place
    const fixedArtificial = artificial.map((a: Assignment) => ({
      ...a,
      grade: a.grade !== undefined && a.grade !== null ? a.grade : "*",
      outOf: a.outOf !== undefined && a.outOf !== null ? a.outOf : 100,
    }));

    const artificialNames = new Set(fixedArtificial.map((a: any) => a.name));
    const filteredReal = apiAssignments.filter((r) => !artificialNames.has(r.name));
    const allAssignments = [...fixedArtificial, ...filteredReal].sort((a, b) => {
      const parseDate = (date: string) => {
        const [month, day, year] = date.split('/').map(Number);
        return new Date(year < 100 ? 2000 + year : year, month - 1, day);
      };
      return parseDate(b.dueDate).getTime() - parseDate(a.dueDate).getTime();
    });
    const assignmentsWithIds = ensureUniqueAssignmentIds(allAssignments);
    const artificialWithIds = assignmentsWithIds.filter(a => fixedArtificial.some((orig: any) => orig.name === a.name));
    setArtificialAssignments(artificialWithIds);
    setFilteredAssignments(assignmentsWithIds);
    // Calculate summary
    const all = assignmentsWithIds.filter(a => a.grade !== '*');
    const weightsMap = Object.fromEntries(
      (apiCategories.names || []).map((name, i) => [name, apiCategories.weights[i]])
    );
    const nonEmptyCategories = all.reduce((set, a) => {
      if (!set.has(a.category)) set.add(a.category);
      return set;
    }, new Set<string>());
    const adjustedWeights = Object.entries(weightsMap).filter(([name]) =>
      nonEmptyCategories.has(name)
    );
    const totalAdjustedWeight = adjustedWeights.reduce((sum, [, w]) => sum + w, 0);
    const normalizedWeights = Object.fromEntries(
      adjustedWeights.map(([name, weight]) => [name, (weight / totalAdjustedWeight) * 100])
    );
    setCourseSummary(calculateGradeSummary(all, normalizedWeights));
  }, [apiAssignments, apiCategories, isEnabled, className, corNumId, section, gbId, selectedCategory]);


  useEffect(() => {
    // Use the actual term grade if no calculated grade is available
    let value: number;
    
    if (courseSummary.courseTotal === '*') {
      // Use the actual term grade from API, handle "--" case
      if (currTerm.total === "--" || currTerm.total === undefined || currTerm.total === null) {
        value = 100; // Animate to 100 when grade is "--"
      } else {
        value = Number(currTerm.total);
      }
    } else {
      value = Number(courseSummary.courseTotal);
    }
    
    animatedGrade.value = withTiming(value, {
      duration: 0,
      easing: Easing.inOut(Easing.ease),
    });
  }, [courseSummary.courseTotal, currTerm.total]);

  useAnimatedReaction(
    () => animatedGrade.value,
    (currentValue) => {
      runOnJS(setDisplayGrade)(currentValue);
    }
  );

  // Fetch API assignments only when identifiers change
  useEffect(() => {
    fetchApiAssignments();
  }, [fetchApiAssignments]);

  // Mesh assignments whenever isEnabled, apiAssignments, or apiCategories change
  useEffect(() => {
    meshAssignments();
  }, [meshAssignments]);

  // Refresh data when returning to this screen
  useFocusEffect(
    React.useCallback(() => {
      meshAssignments();
    }, [meshAssignments])
  );

  const { openModal, onSubmit } = useAddAssignmentSheet();

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () =>
        isEnabled ? (
          <TouchableOpacity
            onPress={async () => {
              openModal({
                className: className || "",
                classId: classId,
                corNumId: corNumId,
                section: section,
                gbId: gbId,
                selectedCategory,
                currTerm: termMap[selectedCategory],
                artificialAssignments,
                setArtificialAssignments,
                setFilteredAssignments,
                filteredAssignments,
                categories: apiCategories.names,
                setCourseSummary,
                calculateGradeSummary,
                isEnabled,
                meshAssignments,
              });
              // Wait for assignment to be added, then re-mesh assignments
              // You may need to trigger meshAssignments after onSubmit in your modal logic
            }}
          >
            <Ionicons
              name="add-outline"
              size={24}
              color="white"
              style={{ marginRight: 15 }}
            />
          </TouchableOpacity>
        ) : null,
    });
  }, [
    isEnabled,
    navigation,
    openModal,
    className,
    classId,
    selectedCategory,
    artificialAssignments,
    setArtificialAssignments,
    setFilteredAssignments,
    calculateGradeSummary,
    meshAssignments,
  ]);


  // Use a class-specific key for showCalculated
  const showCalculatedKey = classId ? `showCalculated_${className}_${classId}` : `showCalculated_${className}`;


  // Load showCalculated from AsyncStorage on initial mount and on focus
  useEffect(() => {
    const loadShowCalculated = async () => {
      const value = await AsyncStorage.getItem(showCalculatedKey);
      if (value !== null) {
        setIsEnabled(value === 'true');
      } else {
        setIsEnabled(false);
      }
    };
    loadShowCalculated();
  }, [showCalculatedKey, meshAssignments]);

const handleToggle = async () => {
  if (isEnabled === null) return;
  const newValue = !isEnabled;
  await AsyncStorage.setItem(showCalculatedKey, newValue.toString());
  setIsEnabled(newValue);
};

const handleResetArtificialAssignments = async () => {
  const data = await AsyncStorage.getItem("artificialAssignments");
  if (!data || !className) return;

  const parsed = JSON.parse(data);
  // console.log("BEFORE RESET:", JSON.stringify(parsed, null, 2));

  // Get relevant terms for the current selected category
  const relevantTerms = getRelevantTerms(selectedCategory);
  
  // For SM1/SM2, also include the semester term itself for resetting
  const termsToReset = [...relevantTerms];
  if (selectedCategory === "SM1 Grade" || selectedCategory === "SM2 Grades") {
    termsToReset.push(selectedCategory.split(" ")[0]); // Add "SM1" or "SM2"
  }

  // Remove only the keys that match the relevant terms for this class
  termsToReset.forEach(term => {
    const storageKey = `${className}_${corNumId}_${section}_${gbId}_${term}`;
    if (parsed[storageKey]) {
      delete parsed[storageKey];
    }
    
    // For individual terms, also delete the old format (full term name)
    if (term === selectedCategory.split(" ")[0]) {
      const oldStorageKey = `${className}_${corNumId}_${section}_${gbId}_${selectedCategory}`;
      if (parsed[oldStorageKey]) {
        delete parsed[oldStorageKey];
      }
    }
  });

  await AsyncStorage.setItem("artificialAssignments", JSON.stringify(parsed));

  // Clear artificial assignments that belong to the relevant terms
  setArtificialAssignments(prev => prev.filter(assignment =>
    !termsToReset.includes(assignment.term as TermLabel)
  ));

  meshAssignments(); // Re-mesh assignments after reset
};

  const theme = useColorScheme();
  const highlightColor = theme === 'dark' ? '#3b5795' : "#a4bfed";
  const backgroundColor = theme === 'dark' ? '#030014' : "#ffffff";

  return (
    <TouchableWithoutFeedback onPress={Keyboard.dismiss} accessible={false}>
      <View className="bg-primary flex-1">
        <Stack.Screen
          options={{
            title: decodeURIComponent(formattedName || "Class"),
            headerStyle: { backgroundColor: "#2563eb" },
            headerTintColor: "#fff",
            headerTitleStyle: {
              fontWeight: "bold",
              fontSize: 18,
            },
            headerBackTitle: "Classes",
          }}
        />
        
        <ScrollView>
          <View className="flex-row items-center">
            <View className="px-5">
              <View className="relative w-[50] h-[50] mt-6">
                <PieChart
                  widthAndHeight={50}
                  series={[
                    { value: Math.min(displayGrade, 100), color: highlightColor },
                    { value: 100 - Math.min(displayGrade, 100), color: backgroundColor },
                  ]}
                />
                <Text className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 text-highlightText font-bold text-sm">
                  {(() => {
                    // Use actual term grade if no calculated grade is available
                    const grade = courseSummary.courseTotal === '*' 
                      ? currTerm.total 
                      : Number(courseSummary.courseTotal);
                    
                    if (grade === "--" || grade === undefined || grade === null) {
                      return '--';
                    }
                    
                    const numGrade = typeof grade === 'string' ? parseFloat(grade) : grade;
                    
                    if (isNaN(numGrade)) {
                      return '--';
                    }
                    
                    return numGrade === 100 
                      ? '100%' 
                      : `${numGrade.toFixed(1)}%`;
                  })()}
                </Text>
              </View>
            </View>
            <View className="w-[80%]">
              <View className="mt-6 pr-5 justify-center">
                <TouchableOpacity
                  onPress={() => bottomSheetRef.current?.snapToIndex(0)}
                  className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full"
                >
                  <Text className="text-base text-main">{selectedCategory}</Text>
                </TouchableOpacity>
              </View>
            </View>
          </View>
          
          {apiCategories.names.length > 0 && (
            <><View className="flex-row mt-4 items-center px-5 justify-between">
              <Text className="text-accent text-base font-medium">Show Calculated</Text>
              <Switch value={!!isEnabled} onValueChange={handleToggle} />
            </View>
            <View className="px-5 mt-4 space-y-2">
                <View className="flex-row justify-between mb-2">
                  <Text className="text-highlightText font-bold text-base">Category</Text>
                  <Text className="text-highlightText font-bold text-base">Weight</Text>
                </View>
                <View className="h-[1px] bg-accent opacity-30 my-1" />
                {apiCategories.names.map((name, index) => (
                  <View key={`row-${index}`}>
                    <View className="py-1">
                      <View className="flex-row justify-between items-center">
                        <View className="rounded-md bg-highlight px-2">
                          <Text className="text-sm text-highlightText font-bold">{name}</Text>
                        </View>
                        <Text className="text-sm text-slate-400 font-bold">
                          Avg: {(courseSummary?.categories[name]?.average?.toFixed(1) ?? "--")}%
                          {" • "}
                          Weight: {(apiCategories.weights[index] ?? 0).toFixed(1)}%
                          {courseSummary.categories[name]
                            ? courseSummary.categories[name].weight.toFixed(1) !==
                              (apiCategories.weights[index] ?? 0).toFixed(1)
                              ? ` → ${courseSummary.categories[name].weight.toFixed(1)}%`
                              : ""
                            : " → 0%"}
                        </Text>
                      </View>
                    </View>

                    {index !== apiCategories.names.length - 1 && (
                      <View className="h-[1px] bg-accent opacity-30 my-1" />
                    )}
                  </View>
                ))}
                <View className="h-[1px] bg-accent opacity-30 my-1" />
              </View></>
          )}
          
          <AnimatePresence>
            {isEnabled && apiCategories.names.length > 0 && (
              <MotiView
                key={`reset-${isEnabled}`}
                from={{ opacity: 0, height: 0, marginTop: 0 }}
                animate={{ opacity: 1, height: 56, marginTop: 16 }}
                exit={{ opacity: 0, height: 0, marginTop: 0 }}
                transition={{
                  type: "spring",
                  damping: 20,
                  stiffness: 300,
                  mass: 0.4,
                  overshootClamping: true,
                  restDisplacementThreshold: 0.01,
                  restSpeedThreshold: 0.01
                }}
                style={{  marginHorizontal: 16 }}
                pointerEvents={isEnabled ? "auto" : "none"}
              >
                <TouchableOpacity
                  onPress={handleResetArtificialAssignments}
                  className="bg-cardColor items-center rounded-lg"
                >
                  <Text className="text-highlightText font-medium py-3 text-lg">Reset Assignments</Text>
                </TouchableOpacity>
              </MotiView>
            )}
          </AnimatePresence>
          <FlatList
            data={filteredAssignments}
            renderItem={({ item }: { item: Assignment }) => (
              <AnimatePresence >
                <MotiView
                  from={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                >
                  <AssignmentCard
                    {...item}
                    editing={!!isEnabled}
                    classId={classId}
                    corNumId={corNumId}
                    section={section}
                    gbId={gbId}
                  />
                </MotiView>
              </AnimatePresence>
            )}
            keyExtractor={(item) => item.id || `${item.className}-${item.name}-${item.term}-${item.dueDate}`}
            className="mt-6 pb-8 px-3"
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
    </TouchableWithoutFeedback>
  );
};

export default ClassDetails;