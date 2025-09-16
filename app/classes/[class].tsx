import {
  View,
  Text,
  TouchableOpacity,
  FlatList,
  Keyboard,
  TouchableWithoutFeedback,
  Switch,
  useColorScheme,
  Animated,
  StyleSheet,
  RefreshControl,
} from "react-native";
import AnimatedReanimated, {
  useSharedValue,
  useAnimatedReaction,
  withTiming,
  runOnJS,
  Easing,
  useAnimatedStyle,
} from 'react-native-reanimated';
import MaskedView from '@react-native-masked-view/masked-view';
import { LinearGradient } from 'react-native-linear-gradient';
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
import SkeletonAssignment from '@/components/SkeletonAssignment';

const bucketMap: Record<TermLabel, string> = {
  "Q1 Grades": "TERM 3",
  "Q2 Grades": "TERM 6",
  "SM1 Grade": "SEM 1",
  "Q3 Grades": "TERM 9",
  "Q4 Grades": "TERM 12",
  "SM2 Grades": "SEM 2",
};

const getRelevantTerms = (selectedCategory: TermLabel): string[] => {
  switch (selectedCategory) {
    case "SM1 Grade":
      return ["Q1", "Q2"];
    case "SM2 Grades":
      return ["Q3", "Q4"];
    default:
      return [selectedCategory.split(" ")[0]];
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
  total: number | string;
};

const ClassDetails = () => {
  const [isEnabled, setIsEnabled] = useState<boolean | null>(null);
  const [displayGrade, setDisplayGrade] = useState(0);
  const [loading, setLoading] = useState(true);
  const [waitingForRetry, setWaitingForRetry] = useState(false);
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
  const [apiCategories, setApiCategories] = useState<{ names: string[]; weights: number[] }>({ names: [], weights: [] });
  const [apiAssignments, setApiAssignments] = useState<Assignment[]>([]);
  const [lastFetchTime, setLastFetchTime] = useState<number>(0);
  const [refreshing, setRefreshing] = useState<boolean>(false);
  const CACHE_DURATION = 10 * 60 * 1000; // 10 minutes

  // Debug function to check cache status
  const checkCacheStatus = async () => {
    const cacheKey = `assignments_${className}_${stuId}_${corNumId}_${section}_${gbId}_${selectedCategory}`;
    try {
      const cachedData = await AsyncStorage.getItem(cacheKey);
      if (cachedData) {
        const parsed = JSON.parse(cachedData);
        const cacheAge = Date.now() - (parsed.timestamp || 0);
        // console.log('Cache status:', {
        //   key: cacheKey,
        //   age: Math.round(cacheAge / 1000) + 's',
        //   isValid: cacheAge < CACHE_DURATION,
        //   assignmentsCount: parsed.assignments?.length || 0,
        //   categoriesCount: parsed.categories?.names?.length || 0
        // });
      } else {
        // console.log('No cache found for key:', cacheKey);
      }
    } catch (error) {
      console.log('Cache check error:', error);
    }
  };

  // Function to clear cache for debugging
  const clearCache = async () => {
    const cacheKey = `assignments_${className}_${stuId}_${corNumId}_${section}_${gbId}_${selectedCategory}`;
    await AsyncStorage.removeItem(cacheKey);
    // console.log('Cache cleared for:', cacheKey);
  };

  // Handle pull-to-refresh
  const handleRefresh = async () => {
    // console.log('Pull-to-refresh triggered');
    await fetchApiAssignments(true); // Force refresh
  };

  const fetchApiAssignments = async (forceRefresh = false) => {
    if (!className || !stuId || !corNumId || !section || !gbId || !selectedCategory) {
      setLoading(false);
      setWaitingForRetry(false);
      return;
    }

    const cacheKey = `assignments_${className}_${stuId}_${corNumId}_${section}_${gbId}_${selectedCategory}`;
    const now = Date.now();

    // Debug: Check cache status
    await checkCacheStatus();

    // Check cache if not forcing refresh
    if (!forceRefresh) {
      try {
        const cachedData = await AsyncStorage.getItem(cacheKey);
        if (cachedData) {
          const parsed = JSON.parse(cachedData);
          const cacheAge = now - (parsed.timestamp || 0);
          
          // Use cache if it's less than CACHE_DURATION old
          if (cacheAge < CACHE_DURATION) {
            // console.log('Using cached assignments data, age:', Math.round(cacheAge / 1000), 'seconds');
            setApiAssignments(parsed.assignments || []);
            setApiCategories(parsed.categories || { names: [], weights: [] });
            setLastFetchTime(now); // Update last fetch time even when using cache
            setLoading(false);
            setWaitingForRetry(false);
            return;
          } else {
            // console.log('Cache expired, age:', Math.round(cacheAge / 1000), 'seconds');
          }
        }
      } catch (error) {
        console.log('Cache read error:', error);
      }
    }

    // console.log('Fetching fresh assignments data from API');
    setLoading(true);
    setWaitingForRetry(true);
    if (forceRefresh) {
      setRefreshing(true);
    }
    const bucket = bucketMap[selectedCategory as TermLabel];
    try {
      const result = await fetchGradeInfo({ stuId, corNumId, section, gbId, bucket });
      
      // Only stop loading if retries are complete or there was no auth error
      if (result.success) {
        // Success - stop loading immediately
        setLoading(false);
        setWaitingForRetry(false);
      } else if (result.retryCount !== undefined && result.retryCount >= 1) {
        // Retries exhausted - stop loading
        setLoading(false);
        setWaitingForRetry(false);
      } else if (!result.wasAuthError) {
        // No auth error - stop loading
        setLoading(false);
        setWaitingForRetry(false);
      } else {
        // Auth error with retries pending - keep loading
        setWaitingForRetry(true);
      }
      
      if (!result.success) {
        // console.log('Fetch failed, result:', result);
        // Only set to empty if we don't have existing data
        if (apiAssignments.length === 0) {
          // Try to use stale cache if available
          try {
            const staleCache = await AsyncStorage.getItem(cacheKey);
            if (staleCache) {
              const parsed = JSON.parse(staleCache);
              setApiAssignments(parsed.assignments || []);
              setApiCategories(parsed.categories || { names: [], weights: [] });
              // console.log('Using stale cache because fetch failed');
            } else {
              setApiAssignments([]);
              setApiCategories({ names: [], weights: [] });
            }
          } catch (error) {
            // console.log('Stale cache read error:', error);
            setApiAssignments([]);
            setApiCategories({ names: [], weights: [] });
          }
        }
        return;
      }
      
      const backendData = result?.data?.data;
      // console.log('backendData.gradebook length:', backendData?.gradebook?.length);
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
          meta: a.meta ?? [],
        }))
      ) ?? [];
      // console.log('Fetched assignments count:', assignments.length);
      setApiAssignments(assignments);
      const categories = {
        names: backendData?.gradebook?.map((cat: any) => cat.category) ?? [],
        weights: backendData?.gradebook?.map((cat: any) => cat.weight) ?? []
      };
      setApiCategories(categories);

      // Cache the data
      const cacheData = {
        assignments,
        categories,
        timestamp: now
      };
      await AsyncStorage.setItem(cacheKey, JSON.stringify(cacheData));
      setLastFetchTime(now);
      
      // Stop loading since we have successful data
      setLoading(false);
      setWaitingForRetry(false);
    } catch (err) {
      console.error('Error fetching assignments:', err);
      // Only set to empty if we don't have existing data
      if (apiAssignments.length === 0) {
        // Try to use stale cache if available
        try {
          const staleCache = await AsyncStorage.getItem(cacheKey);
          if (staleCache) {
            const parsed = JSON.parse(staleCache);
            setApiAssignments(parsed.assignments || []);
            setApiCategories(parsed.categories || { names: [], weights: [] });
            // console.log('Using stale cache because fetch threw error');
          } else {
            setApiAssignments([]);
            setApiCategories({ names: [], weights: [] });
          }
        } catch (error) {
          // console.log('Stale cache read error:', error);
          setApiAssignments([]);
          setApiCategories({ names: [], weights: [] });
        }
      }
    } finally {
      // Stop loading if we're not waiting for retry or if there was an error
      setLoading(false);
      setWaitingForRetry(false);
      setRefreshing(false);
    }
  };

  const meshAssignments = async () => {
    // console.log('meshAssignments called:', {
    //   apiAssignmentsLength: apiAssignments.length,
    //   filteredAssignmentsLength: filteredAssignments.length,
    //   isEnabled,
    //   selectedCategory
    // });
    
    const data = await AsyncStorage.getItem("artificialAssignments");
    if (!data) {
      // If apiAssignments is empty and we don't have artificial assignments data, don't clear everything
      if (apiAssignments.length === 0 && filteredAssignments.length > 0) {
        console.log('No artificial data and no API data, keeping existing assignments');
        return;
      }
      
      const realWithIds = ensureUniqueAssignmentIds(apiAssignments);
      setArtificialAssignments([]);
      setFilteredAssignments(realWithIds);
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
    const relevantTerms = getRelevantTerms(selectedCategory);
    
    let allArtificialAssignments: Assignment[] = [];
    
    const termsToCheck = [...relevantTerms];
    if (selectedCategory === "SM1 Grade" || selectedCategory === "SM2 Grades") {
      termsToCheck.push(selectedCategory.split(" ")[0]);
    }
    
    termsToCheck.forEach(term => {
      const storageKey = `${className}_${corNumId}_${section}_${gbId}_${term}`;
      const classAssignments = parsed[storageKey] ?? [];
      allArtificialAssignments = [...allArtificialAssignments, ...classAssignments];
      
      if (term === selectedCategory.split(" ")[0]) {
        const oldStorageKey = `${className}_${corNumId}_${section}_${gbId}_${selectedCategory}`;
        const oldAssignments = parsed[oldStorageKey] ?? [];
        allArtificialAssignments = [...allArtificialAssignments, ...oldAssignments];
      }
    });
    
    const artificial = isEnabled ? allArtificialAssignments : [];

    const fixedArtificial = artificial.map((a: Assignment) => ({
      ...a,
      grade: a.grade !== undefined && a.grade !== null ? a.grade : "*",
      outOf: a.outOf !== undefined && a.outOf !== null ? a.outOf : 100,
    }));

    const artificialNames = new Set(fixedArtificial.map((a: any) => a.name));
    // console.log('Processing assignments:', {
    //   artificialCount: fixedArtificial.length,
    //   artificialNames: Array.from(artificialNames),
    //   apiAssignmentsCount: apiAssignments.length
    // });
    
    // If we have artificial assignments but no API assignments, use only artificial ones
    let filteredReal: Assignment[];
    if (apiAssignments.length === 0 && fixedArtificial.length > 0) {
      // console.log('No API assignments but have artificial, using only artificial assignments');
      filteredReal = [];
    } else if (apiAssignments.length === 0 && fixedArtificial.length === 0) {
      // If both are empty, preserve existing assignments if they exist
      if (filteredAssignments.length > 0) {
        // console.log('Both API and artificial are empty, preserving existing assignments');
        return;
      }
      filteredReal = [];
    } else {
      filteredReal = apiAssignments.filter((r) => !artificialNames.has(r.name));
    }
    
    // console.log('filteredReal count:', filteredReal.length);
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
  };


  useEffect(() => {
    let value: number;
    
    if (courseSummary.courseTotal === '*') {
      if (currTerm.total === "--" || currTerm.total === undefined || currTerm.total === null) {
        value = 100;
      } else {
        value = Number(currTerm.total);
      }
    } else {
      value = Number(courseSummary.courseTotal);
    }
    
    // Check if the jump is too large (50+ points) to skip animation
    const currentValue = animatedGrade.value;
    const difference = Math.abs(value - currentValue);
    
    if (difference >= 50) {
      // Skip animation for large jumps
      animatedGrade.value = value;
    } else {
      // Normal animation for smaller changes
      animatedGrade.value = withTiming(value, {
        duration: 200,
        easing: Easing.inOut(Easing.ease),
      });
    }
  }, [courseSummary.courseTotal, currTerm.total]);

  useAnimatedReaction(
    () => animatedGrade.value,
    (currentValue) => {
      runOnJS(setDisplayGrade)(currentValue);
    }
  );

  useEffect(() => {
    // Only fetch if we don't have data or if this is the initial load
    if (apiAssignments.length === 0 && apiCategories.names.length === 0) {
      // console.log('Initial load - fetching assignments');
      fetchApiAssignments();
    }
  }, [className, stuId, corNumId, section, gbId, selectedCategory]);

  useEffect(() => {
    const runMeshAssignments = async () => {
      await meshAssignments();
    };
    runMeshAssignments();
  }, [apiAssignments, apiCategories, isEnabled, selectedCategory]);

  useFocusEffect(
    React.useCallback(() => {
      const refreshArtificialAssignments = async () => {
        // console.log('Screen focused - refreshing artificial assignments only');
        
        // Only refresh artificial assignments when screen is focused
        // This ensures updates made in assignment detail view are reflected
        // without triggering a full API reload
        await meshAssignments();
      };
      refreshArtificialAssignments();
    }, [meshAssignments])
  );

  const { openModal } = useAddAssignmentSheet();

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

  const showCalculatedKey = classId ? `showCalculated_${className}_${classId}` : `showCalculated_${className}`;

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
  // Immediately refresh assignments after toggling
  await meshAssignments();
};

const handleResetArtificialAssignments = async () => {
  const data = await AsyncStorage.getItem("artificialAssignments");
  if (!data || !className) return;

  const parsed = JSON.parse(data);

  const relevantTerms = getRelevantTerms(selectedCategory);
  
  const termsToReset = [...relevantTerms];
  if (selectedCategory === "SM1 Grade" || selectedCategory === "SM2 Grades") {
    termsToReset.push(selectedCategory.split(" ")[0]);
  }

  termsToReset.forEach(term => {
    const storageKey = `${className}_${corNumId}_${section}_${gbId}_${term}`;
    if (parsed[storageKey]) {
      delete parsed[storageKey];
    }
    
    if (term === selectedCategory.split(" ")[0]) {
      const oldStorageKey = `${className}_${corNumId}_${section}_${gbId}_${selectedCategory}`;
      if (parsed[oldStorageKey]) {
        delete parsed[oldStorageKey];
      }
    }
  });

  await AsyncStorage.setItem("artificialAssignments", JSON.stringify(parsed));

  setArtificialAssignments(prev => prev.filter(assignment =>
    !termsToReset.includes(assignment.term as TermLabel)
  ));

  meshAssignments();
};

  const theme = useColorScheme();
  const highlightColor = theme === 'dark' ? '#3b5795' : "#a4bfed";
  const backgroundColor = theme === 'dark' ? '#030014' : "#ffffff";
  const indicatorColor = theme === 'dark' ? '#ffffff' : '#000000';

  // console.log(filteredAssignments);
  return (
    <TouchableWithoutFeedback onPress={Keyboard.dismiss} accessible={false}>
      <View className="bg-primary flex-1">
        <Stack.Screen
          options={{
            title: decodeURIComponent(formattedName || "Class"),
            headerStyle: { backgroundColor: "#2563eb" },
            headerTintColor: "#ffffff",
            headerTitleStyle: {
              fontWeight: "bold",
              fontSize: 18,
            },
            headerBackTitle: "Classes",
          }}
        />
        
        <ScrollView
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor={indicatorColor}
              colors={[indicatorColor]}
            />
          }
        >
          <View className="flex-row items-center">
            <View className="px-5">
                <View className="relative w-[50px] h-[50px] mt-6 flex items-center justify-center">
                  <PieChart
                    widthAndHeight={55}
                    series={[
                      { value: Math.min(displayGrade, 100), color: highlightColor },
                      { value: 100 - Math.min(displayGrade, 100), color: backgroundColor },
                    ]}
                  />
                  <View className="absolute inset-0 flex items-center justify-center">
                    <Text className="text-highlightText font-bold text-sm text-center leading-[20px] w-[50px] h-[20px]">
                      {(() => {
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
                        return `${numGrade.toFixed(2)}`;
                      })()}
                    </Text>
                  </View>
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

          {!loading && apiCategories.names.length > 0 && (
            <>
              <View className="flex-row mt-4 items-center px-5 justify-between">
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
                          <Text className="text-sm text-highlightText font-bold">{
                            (() => {
                              const weight = apiCategories.weights[index] ?? 0;
                              const weightString = `Weight: ${weight.toFixed(1)}%`;
                              const avgString = `Avg: ${(courseSummary?.categories[name]?.average?.toFixed(1) ?? "--")}% • `;
                              const fullWeightText = avgString + weightString;

                              const maxRowLength = 38;
                              const availableForCategory = Math.max(8, maxRowLength - fullWeightText.length);

                              return name.length > availableForCategory
                                ? name.substring(0, availableForCategory - 3) + '...'
                                : name;
                            })()
                          }</Text>
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
              </View>
            </>
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
                        data={loading || waitingForRetry ? Array.from({ length: 8 }) : filteredAssignments}
            renderItem={({ item, index }) => (
              loading || waitingForRetry ? (
                <SkeletonAssignment key={`skeleton-${index}`} />
              ) : (
                <AnimatePresence key={(item as Assignment).id || `${(item as Assignment).className}-${(item as Assignment).name}-${(item as Assignment).term}-${(item as Assignment).dueDate}`}>
                  <MotiView
                    from={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                  >
                    <AssignmentCard
                      {...(item as Assignment)}
                      editing={!!isEnabled}
                      classId={classId}
                      corNumId={corNumId}
                      section={section}
                      gbId={gbId}
                    />
                  </MotiView>
                </AnimatePresence>
              )
            )}
            keyExtractor={(item, index) => loading || waitingForRetry ? `skeleton-${index}` : ((item as Assignment).id || `${(item as Assignment).className}-${(item as Assignment).name}-${(item as Assignment).term}-${(item as Assignment).dueDate}`)}
            className="mt-6 pb-8 px-3"
            scrollEnabled={false}
            ItemSeparatorComponent={() => <View className="h-4" />}
            ListEmptyComponent={
              loading || waitingForRetry ? null : (
                <View className="mt-10 px-5">
                  <Text className="text-center text-gray-500">No assignments found</Text>
                </View>
              )
            }
          />
        </ScrollView>
      </View>
    </TouchableWithoutFeedback>
  );
};

export default ClassDetails;