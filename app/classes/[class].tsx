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
import { Ionicons } from "@expo/vector-icons";
import AssignmentCard from "@/components/AssignmentCard";
import { useAddAssignmentSheet } from "@/context/AddAssignmentSheetContext";
import { useBottomSheet } from "@/context/BottomSheetContext";
import PieChart from "react-native-pie-chart";

export const ASSIN = [
  {
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
  total: number;
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
    if (!className) return;

    // await AsyncStorage.clear();
    const data = await AsyncStorage.getItem("artificialAssignments");
    if (!data) {
      const real = ASSIN.filter(
        (item) => item.className === className && item.term === selectedCategory.split(" ")[0]
      );

      const all = real.filter(a => a.grade !== '*');
      const weightsMap = Object.fromEntries(
        currTerm.categories.names.map((name, i) => [name, currTerm.categories.weights[i]])
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
      setFilteredAssignments(real);
      setCourseSummary(calculateGradeSummary(all, normalizedWeights));
      return;
    }

    const parsed = JSON.parse(data);
    const classAssignments = parsed[className] ?? [];
    setArtificialAssignments(classAssignments);

    const real = ASSIN.filter(
      (item) => item.className === className && item.term === selectedCategory.split(" ")[0]
    );

    const artificial = isEnabled
      ? classAssignments.filter(
          (item: Assignment) =>
            item.className === className && item.term === selectedCategory.split(" ")[0]
        )
      : [];

    const artificialNames = new Set(artificial.map((a: any) => a.name));
    const filteredReal = real.filter((r) => !artificialNames.has(r.name));

    setFilteredAssignments([...artificial, ...filteredReal]);

    const all = [...artificial, ...filteredReal].filter(a => a.grade !== '*');
    const weightsMap = Object.fromEntries(
      currTerm.categories.names.map((name, i) => [name, currTerm.categories.weights[i]])
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
    // console.log(calculateGradeSummary(all, normalizedWeights));

    setCourseSummary(calculateGradeSummary(all, normalizedWeights));
  }, [className, selectedCategory, isEnabled, currTerm.categories.names, currTerm.categories.weights]);

  useEffect(() => {
    fetchArtificialAssignments();
  }, [fetchArtificialAssignments]);

  useEffect(() => {
    const value =
      courseSummary.courseTotal === '*'
        ? 100
        : Number(courseSummary.courseTotal);
    animatedGrade.value = withTiming(value, {
      duration: 700,
      easing: Easing.inOut(Easing.ease),
    });
  }, [courseSummary.courseTotal]);

  useAnimatedReaction(
    () => animatedGrade.value,
    (currentValue) => {
      runOnJS(setDisplayGrade)(currentValue);
    }
  );

  useFocusEffect(
    useCallback(() => {
      fetchArtificialAssignments();
    }, [fetchArtificialAssignments])
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
            }
            }
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
  delete parsed[className];
  await AsyncStorage.setItem("artificialAssignments", JSON.stringify(parsed));

  fetchArtificialAssignments();
};
  // Animation for Reset Assignments button (Reanimated)
  const resetAnim = useSharedValue(0);
  const [showReset, setShowReset] = useState(false);

  useEffect(() => {
    if (!isReady) return;
    if (isEnabled) {
      setShowReset(true);
      resetAnim.value = withTiming(1, { duration: 300 });
    } else {
      resetAnim.value = withTiming(0, { duration: 300 }, () => {
        runOnJS(setShowReset)(false);
      });
    }
  }, [isEnabled, isReady]);

  const animatedResetStyle = useAnimatedStyle(() => ({
    opacity: resetAnim.value,
    transform: [
      { translateY: resetAnim.value * 20 - 20 },
      { scaleY: 0.85 + resetAnim.value * 0.15 },
    ],
    marginTop: 16,
  }));

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
                  { value: displayGrade, color: highlightColor },
                  { value: 100 - displayGrade, color: backgroundColor },
                ]}
              />
              <Text className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 text-highlightText font-bold text-sm">
                {courseSummary.courseTotal === '*'
                  ? '--'
                  : Number(courseSummary.courseTotal) === 100
                  ? '100%'
                  : `${Number(courseSummary.courseTotal).toFixed(1)}%`}
              </Text>
            </View>
          </View>
          <View className="w-[80%]">
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
                      <View
                        className="bg-highlight h-2"
                        style={{ width: `${courseSummary.categories[name].average}%` }}
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
          {showReset && (
            <Animated.View
              style={animatedResetStyle}
              pointerEvents={isEnabled ? "auto" : "none"}
            >
              <TouchableOpacity
                onPress={handleResetArtificialAssignments}
                className="mx-4 bg-cardColor items-center rounded-lg"
              >
                <Text className="text-highlightText font-medium py-3 text-lg">Reset Assignments</Text>
              </TouchableOpacity>
            </Animated.View>
          )}
          <FlatList
            data={filteredAssignments}
            renderItem={({ item }: { item: Assignment }) => (
              <AssignmentCard {...item} editing={isEnabled} />
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
    </TouchableWithoutFeedback>
  );
};

export default ClassDetails;