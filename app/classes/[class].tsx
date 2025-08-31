import {
  View,
  Text,
  ScrollView,
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



export const ASSIN = [
  {
    id: "assign_bio_pig_practical",
    className: "BIOLOGY_1_HONORS",
    name: "Pig Practical",
    term: "Q1",
    category: "Major",
    grade: "96",
    outOf: 100,
    dueDate: "05/09/25",
    artificial: false,
  },
  {
    id: "assign_bio_pig_dissection",
    className: "BIOLOGY_1_HONORS",
    name: "Pig Disection #1",
    term: "Q1",
    category: "Labs",
    grade: "95",
    outOf: 100,
    dueDate: "05/06/25",
    artificial: false,
  },
  {
    id: "assign_bio_biodiv_threats",
    className: "BIOLOGY_1_HONORS",
    name: "Biodiv. Threats",
    term: "Q2",
    category: "Daily",
    grade: "100",
    outOf: 100,
    dueDate: "04/10/25",
    artificial: false,
  },
  {
    id: "assign_precalc_trig_test",
    className: "AP_PRECALCULUS",
    name: "Test Intro to Trig",
    term: "SM1",
    category: "Major",
    grade: "89",
    outOf: 100,
    dueDate: "04/10/25",
    artificial: false,
  },
];

const bucketMap: Record<TermLabel, string> = {
  "Q1 Grades": "TERM 3",
  "Q2 Grades": "TERM 6",
  "SM1 Grade": "SEM 1",
  "Q3 Grades": "TERM 9",
  "Q4 Grades": "TERM 12",
  "SM2 Grades": "SEM 2",
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
  const [isEnabled, setIsEnabled] = useState(false);
  const [isReady, setIsReady] = useState(false);
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
  const [filteredAssignments, setFilteredAssignments] = useState<Assignment[]>(() => {
    if (!classParam || !selectedCategory) return [];
    return ASSIN.filter(
      (item) =>
        item.className === classParam &&
        item.term === selectedCategory.split(" ")[0] &&
        (!item.artificial || isEnabled)
    );
  });
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

  const fetchArtificialAssignments = useCallback(async () => {
    if (!className || !stuId || !corNumId || !section || !gbId || !selectedCategory) return;

    // Build the correct bucket string using bucketMap and selectedCategory
    // selectedCategory is e.g. "Q1 Grades", "Q2 Grades", etc.
    const bucket = bucketMap[selectedCategory as TermLabel];
    let apiAssignments: Assignment[] = [];
    let apiCategories: { names: string[]; weights: number[] } = { names: [], weights: [] };
    try {
      // Call the backend API to get assignments and categories
      const result = await fetchGradeInfo({ stuId, corNumId, section, gbId, bucket });

      const backendData = result?.data?.data;

      // console.log(backendData);
      apiAssignments = backendData?.gradebook?.flatMap((cat: any) =>
        (cat.assignments ?? []).map((a: any, index: number) => ({
          id: `${cat.category}-${index}-${a.name}`, // ensure unique ID
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

      // console.log(apiAssignments);

      apiCategories = {
        names: backendData?.gradebook?.map((cat: any) => cat.category) ?? [],
        weights: backendData?.gradebook?.map((cat: any) => cat.weight) ?? []
      };
      // removed previous console log
    } catch (err) {
      // fallback to empty
      apiAssignments = [];
      apiCategories = { names: [], weights: [] };
    }

    // await AsyncStorage.clear();
    const data = await AsyncStorage.getItem("artificialAssignments");
    if (!data) {
      // Ensure all assignments have unique IDs
      const realWithIds = ensureUniqueAssignmentIds(apiAssignments);

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

      setArtificialAssignments([]);
      setFilteredAssignments(realWithIds);
      setCourseSummary(calculateGradeSummary(all, normalizedWeights));
      return;
    }

    const parsed = JSON.parse(data);
    // Use classId to create unique storage key for identical classes
    const storageKey = classId ? `${className}_${classId}` : className;
    const classAssignments = parsed[storageKey] ?? parsed[className] ?? []; // Fallback to old format for backwards compatibility

    // Use backend assignments instead of ASSIN
    const real = apiAssignments;

    const artificial = isEnabled
      ? classAssignments.filter(
          (item: Assignment) =>
            item.className === className && item.term === selectedCategory.split(" ")[0]
        )
      : [];

    const artificialNames = new Set(artificial.map((a: any) => a.name));
    const filteredReal = real.filter((r) => !artificialNames.has(r.name));

    // Combine and ensure unique IDs for all assignments
    const allAssignments = [...artificial, ...filteredReal];
    const assignmentsWithIds = ensureUniqueAssignmentIds(allAssignments);
    
    // Separate them back out
    const artificialWithIds = assignmentsWithIds.filter(a => artificial.some((orig: any) => orig.name === a.name));
    setArtificialAssignments(artificialWithIds);
    setFilteredAssignments(assignmentsWithIds);

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
  }, [className, classId, selectedCategory, isEnabled, currTerm.categories.names, currTerm.categories.weights, stuId, corNumId, section, gbId]);


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
      duration: 700,
      easing: Easing.inOut(Easing.ease),
    });
  }, [courseSummary.courseTotal, currTerm.total]);

  useAnimatedReaction(
    () => animatedGrade.value,
    (currentValue) => {
      runOnJS(setDisplayGrade)(currentValue);
    }
  );

  useAnimatedReaction(
    () => animatedGrade.value,
    (currentValue) => {
      runOnJS(setDisplayGrade)(currentValue);
    }
  );

  useFocusEffect(
    useCallback(() => {
      fetchArtificialAssignments();
    }, [])
  );

  const { openModal } = useAddAssignmentSheet();

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () =>
        isEnabled ? (
          <TouchableOpacity
            onPress={() => {
              openModal({
                className: className || "",
                classId: classId, // Pass classId to differentiate identical classes
                selectedCategory,
                currTerm: termMap[selectedCategory],
                artificialAssignments,
                setArtificialAssignments,
                setFilteredAssignments,
                ASSIN,
                setCourseSummary,
                calculateGradeSummary,
                isEnabled,
              });
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
  ]);

  useEffect(() => {
    const loadShowCalculated = async () => {
      const value = await AsyncStorage.getItem('showCalculated');
      if (value !== null) {
        setIsEnabled(value === 'true');
      }
      setIsReady(true);
    };
    loadShowCalculated();
  }, []);

const handleToggle = async () => {
  const newValue = !isEnabled;
  setIsEnabled(newValue);
  await AsyncStorage.setItem('showCalculated', newValue.toString());
};

const handleResetArtificialAssignments = async () => {
  const data = await AsyncStorage.getItem("artificialAssignments");
  if (!data || !className) return;

  const parsed = JSON.parse(data);
  // Use classId to create unique storage key for identical classes
  const storageKey = classId ? `${className}_${classId}` : className;
  delete parsed[storageKey];
  // Also delete old format key for backwards compatibility
  delete parsed[className];
  await AsyncStorage.setItem("artificialAssignments", JSON.stringify(parsed));

  fetchArtificialAssignments();
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
        <View className="flex-row mt-4 items-center px-5 justify-between">
          <Text className="text-accent text-base font-medium">Show Calculated</Text>
          <Switch value={isEnabled} onValueChange={handleToggle} />
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
                    Avg: {(courseSummary?.categories[name]?.average?.toFixed(1) ?? "--")}%
                    {" • "}
                    Weight: {(currTerm.categories.weights[index] ?? 0).toFixed(1)}%
                    {courseSummary.categories[name]
                      ? courseSummary.categories[name].weight.toFixed(1) !==
                        (currTerm.categories.weights[index] ?? 0).toFixed(1)
                        ? ` → ${courseSummary.categories[name].weight.toFixed(1)}%`
                        : ""
                      : " → 0%"}
                  </Text>
                </View>
                <View className="items-end">
                  {courseSummary.categories[name] && (
                    <View className="h-2 w-[50%] bg-accent rounded-full overflow-hidden mt-1 ">
                      <MotiView
                        animate={{width: `${courseSummary.categories[name].average}%`}}
                        className="bg-highlight h-2"
                        transition={{
                          type: 'spring',
                          damping: 20
                        }}
                        // style={{ width: `${courseSummary.categories[name].average}%` }}
                      />
                    </View>
                  )}
                </View>
              </View>

              {index !== currTerm.categories.names.length - 1 && (
                <View className="h-[1px] bg-accent opacity-30 my-1" />
              )}
            </View>
          ))}
          <View className="h-[1px] bg-accent opacity-30 my-1" />
        </View>
        <ScrollView className="mt-2">
          <AnimatePresence>
            {isEnabled && (
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
                  <AssignmentCard {...item} editing={isEnabled} classId={classId} />
                </MotiView>
              </AnimatePresence>
            )}
            keyExtractor={(item) => item.id || `${item.className}-${item.name}-${item.term}-${item.dueDate}`}
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
    </TouchableWithoutFeedback>
  );
};

export default ClassDetails;