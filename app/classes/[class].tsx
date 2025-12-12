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
  useMemo,
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
import { DataService } from '@/lib/services';
import { logger, Modules } from '@/lib/utils/logger';
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

type TermData = {
  categories: {
    names: string[];
    weights: number[];
  };
  total: number | string;
};

const ClassDetails = () => {
  const [isEnabled, setIsEnabled] = useState<boolean>(false);
  const [isToggling, setIsToggling] = useState<boolean>(false);
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



  const parseTermData = useCallback((param: string | string[] | undefined): TermData => {
    if (typeof param === "string") {
      try {
        return JSON.parse(param);
      } catch {
        return { categories: { names: [], weights: [] }, total: "--" };
      }
    }
    return { categories: { names: [], weights: [] }, total: "--" };
  }, []);

  const termMap: Record<TermLabel, TermData> = useMemo(() => {
    const t1 = parseTermData(searchParams.t1);
    const t2 = parseTermData(searchParams.t2);
    const s1 = parseTermData(searchParams.s1);
    const t3 = parseTermData(searchParams.t3);
    const t4 = parseTermData(searchParams.t4);
    const s2 = parseTermData(searchParams.s2);

    return {
      "Q1 Grades": t1,
      "Q2 Grades": t2,
      "SM1 Grade": s1,
      "Q3 Grades": t3,
      "Q4 Grades": t4,
      "SM2 Grades": s2,
    };
  }, [searchParams.t1, searchParams.t2, searchParams.s1, searchParams.t3, searchParams.t4, searchParams.s2, parseTermData]);

  const formattedName = useMemo(() => formatClassName(className?.toString()), [className]);

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
  
  // Track category changes for refresh logic
  const [previousSelectedCategory, setPreviousSelectedCategory] = useState<TermLabel | null>(null);

  // Filter state
  const [sortOption, setSortOption] = useState<'category' | 'date' | 'grade'>('date');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc'); // desc = recent to oldest for dates
  const [showFilterMenu, setShowFilterMenu] = useState(false);
  const filterMenuOpacity = useSharedValue(0);
  const filterMenuScale = useSharedValue(0.8);

  // Sort assignments function
  const sortAssignments = useCallback((assignments: Assignment[], sortBy: 'category' | 'date' | 'grade', order: 'asc' | 'desc') => {
    return [...assignments].sort((a, b) => {
      let comparison = 0;
      
      switch (sortBy) {
        case 'category':
          comparison = a.category.localeCompare(b.category);
          break;
        case 'date':
          const parseDate = (date: string) => {
            const [month, day, year] = date.split('/').map(Number);
            return new Date(year < 100 ? 2000 + year : year, month - 1, day);
          };
          comparison = parseDate(a.dueDate).getTime() - parseDate(b.dueDate).getTime(); // asc = oldest first, desc = recent first
          break;
        case 'grade':
          const gradeA = a.grade === '*' ? -1 : parseFloat(a.grade) || 0;
          const gradeB = b.grade === '*' ? -1 : parseFloat(b.grade) || 0;
          comparison = gradeA - gradeB;
          break;
      }
      
      return order === 'asc' ? comparison : -comparison;
    });
  }, []);

  // Filter menu animation functions
  const toggleFilterMenu = useCallback(() => {
    if (showFilterMenu) {
      filterMenuOpacity.value = withTiming(0, { duration: 200 });
      filterMenuScale.value = withTiming(0.8, { duration: 200 });
      setTimeout(() => setShowFilterMenu(false), 200);
    } else {
      setShowFilterMenu(true);
      filterMenuOpacity.value = withTiming(1, { duration: 200 });
      filterMenuScale.value = withTiming(1, { duration: 200 });
    }
  }, [showFilterMenu, filterMenuOpacity, filterMenuScale]);

  const animatedFilterMenuStyle = useAnimatedStyle(() => ({
    opacity: filterMenuOpacity.value,
    transform: [{ scale: filterMenuScale.value }],
  }));

  // Handle sort option change
  const handleSortChange = useCallback((newSortOption: 'category' | 'date' | 'grade') => {
    if (sortOption === newSortOption) {
      // If same option, toggle order
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      // New option, set default order
      setSortOption(newSortOption);
      if (newSortOption === 'grade') {
        setSortOrder('desc'); // Grades default to highest first
      } else if (newSortOption === 'date') {
        setSortOrder('desc'); // Dates default to recent first (newest to oldest)
      } else {
        setSortOrder('asc'); // Categories default to A-Z
      }
    }
    toggleFilterMenu();
  }, [sortOption, sortOrder, toggleFilterMenu]);

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
      logger.warn(Modules.PAGE_CLASS, 'Missing required params');
      setLoading(false);
      setWaitingForRetry(false);
      return;
    }

    const bucket = bucketMap[selectedCategory as TermLabel];
    
    if (forceRefresh) {
      logger.info(Modules.PAGE_CLASS, `Force refresh: ${selectedCategory}`);
      setLoading(true);
      setRefreshing(true);
    }
    
    try {
      const result = await DataService.getGradeInfo({ stuId, corNumId, section, gbId, bucket });
      
      if (!result.success) {
        logger.error(Modules.PAGE_CLASS, 'Failed to fetch assignments', result.error);
        setLoading(false);
        setWaitingForRetry(false);
        setRefreshing(false);
        
        if (apiAssignments.length === 0) {
          setApiAssignments([]);
          setApiCategories({ names: [], weights: [] });
        }
        return;
      }
      
      const backendData = result?.data;
      
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
      
      logger.success(Modules.PAGE_CLASS, `Loaded ${assignments.length} assignments`);
      setApiAssignments(assignments);
      
      const categories = {
        names: backendData?.gradebook?.map((cat: any) => cat.category) ?? [],
        weights: backendData?.gradebook?.map((cat: any) => cat.weight) ?? []
      };
      setApiCategories(categories);
      setLastFetchTime(Date.now());
      
    } catch (err) {
      logger.error(Modules.PAGE_CLASS, 'Error fetching assignments', err);
      
      if (apiAssignments.length === 0) {
        setApiAssignments([]);
        setApiCategories({ names: [], weights: [] });
      }
    } finally {
      setLoading(false);
      setWaitingForRetry(false);
      setRefreshing(false);
    }
  };

  const meshAssignments = useCallback(async () => {
    logger.debug(Modules.PAGE_CLASS, 'Meshing assignments', {
      api: apiAssignments.length,
      filtered: filteredAssignments.length,
      enabled: isEnabled,
    });
    
    const data = await AsyncStorage.getItem("artificialAssignments");
    if (!data) {
      if (apiAssignments.length === 0 && filteredAssignments.length > 0) {
        return;
      }
      const realWithIds = ensureUniqueAssignmentIds(apiAssignments);
      const sortedAssignments = sortAssignments(realWithIds, sortOption, sortOrder);
      setArtificialAssignments([]);
      setFilteredAssignments(sortedAssignments);
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
    
    let filteredReal: Assignment[];
    if (apiAssignments.length === 0 && fixedArtificial.length > 0) {
      filteredReal = [];
    } else if (apiAssignments.length === 0 && fixedArtificial.length === 0) {
      if (filteredAssignments.length > 0) {
        return;
      }
      filteredReal = [];
    } else {
      filteredReal = apiAssignments.filter((r) => !artificialNames.has(r.name));
    }
    const allAssignments = [...fixedArtificial, ...filteredReal];
    const assignmentsWithIds = ensureUniqueAssignmentIds(allAssignments);
    const sortedAssignments = sortAssignments(assignmentsWithIds, sortOption, sortOrder);
    const artificialWithIds = sortedAssignments.filter(a => fixedArtificial.some((orig: any) => orig.name === a.name));
    
    logger.debug(Modules.PAGE_CLASS, `Meshed ${sortedAssignments.length} assignments (${artificialWithIds.length} artificial)`);
    
    setArtificialAssignments(artificialWithIds);
    setFilteredAssignments(sortedAssignments);

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
    const newCourseSummary = calculateGradeSummary(all, normalizedWeights);
    logger.debug(Modules.PAGE_CLASS, `Setting course summary: ${newCourseSummary.courseTotal} (isEnabled: ${isEnabled}, assignments: ${all.length})`);
    setCourseSummary(newCourseSummary);
  }, [apiAssignments, apiCategories, isEnabled, selectedCategory, sortOption, sortOrder]);


  useEffect(() => {
    // Don't update grade during toggle to prevent jittery animation
    if (isToggling) return;
    
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
    
    logger.debug(Modules.PAGE_CLASS, `Grade calculation: courseSummary.courseTotal=${courseSummary.courseTotal}, currTerm.total=${currTerm.total}, finalValue=${value}, isEnabled=${isEnabled}`);
    
    // Check if the jump is too large (50+ points) to skip animation
    const currentValue = animatedGrade.value;
    const difference = Math.abs(value - currentValue);
    
    if (difference >= 50) {
      // Skip animation for large jumps
      animatedGrade.value = value;
    } else {
      // Normal animation for smaller changes - use proper timing
      animatedGrade.value = withTiming(value, {
        duration: 600,
        easing: Easing.out(Easing.quad),
      });
    }
  }, [courseSummary.courseTotal, currTerm.total, isEnabled, isToggling]);

  useAnimatedReaction(
    () => animatedGrade.value,
    (currentValue) => {
      runOnJS(setDisplayGrade)(currentValue);
    }
  );

  useEffect(() => {
    const isInitialLoad = apiAssignments.length === 0 && apiCategories.names.length === 0;
    const categoryChanged = previousSelectedCategory !== null && previousSelectedCategory !== selectedCategory;
    
    if (isInitialLoad || categoryChanged) {
      logger.info(Modules.PAGE_CLASS, `Loading ${selectedCategory}`);
      fetchApiAssignments();
    }
    
    setPreviousSelectedCategory(selectedCategory);
  }, [className, stuId, corNumId, section, gbId, selectedCategory]);

  useEffect(() => {
    const runMeshAssignments = async () => {
      await meshAssignments();
    };
    runMeshAssignments();
  }, [apiAssignments, apiCategories, isEnabled, selectedCategory, sortOption, sortOrder]);

  // Separate function for refreshing only artificial assignments on focus
  const refreshArtificialAssignmentsOnFocus = useCallback(async () => {
    logger.debug(Modules.PAGE_CLASS, 'Screen focused - refreshing artificial assignments');
    
    // Only process artificial assignments without triggering API calls
    // This ensures updates made in assignment detail view are reflected
    const data = await AsyncStorage.getItem("artificialAssignments");
    if (!data) {
      // If no artificial data exists, just ensure filtered assignments match API assignments
      if (apiAssignments.length > 0) {
        const realWithIds = ensureUniqueAssignmentIds(apiAssignments);
        const sortedAssignments = sortAssignments(realWithIds, sortOption, sortOrder);
        setFilteredAssignments(sortedAssignments);
        setArtificialAssignments([]);
      }
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
    const filteredReal = apiAssignments.filter((r) => !artificialNames.has(r.name));
    
    const allAssignments = [...fixedArtificial, ...filteredReal];
    const assignmentsWithIds = ensureUniqueAssignmentIds(allAssignments);
    const sortedAssignments = sortAssignments(assignmentsWithIds, sortOption, sortOrder);
    const artificialWithIds = sortedAssignments.filter(a => fixedArtificial.some((orig: any) => orig.name === a.name));
    
    setArtificialAssignments(artificialWithIds);
    setFilteredAssignments(sortedAssignments);

    // Recalculate course summary with updated assignments
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
  }, [apiAssignments, apiCategories, isEnabled, selectedCategory, className, corNumId, section, gbId, sortAssignments, sortOption, sortOrder]);

  useFocusEffect(
    React.useCallback(() => {
      refreshArtificialAssignmentsOnFocus();
    }, [refreshArtificialAssignmentsOnFocus])
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
              style={{ marginLeft:5 }}
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
      try {
        const value = await AsyncStorage.getItem(showCalculatedKey);
        setIsEnabled(value === 'true');
      } catch (error) {
        console.error('Failed to load toggle state:', error);
        setIsEnabled(false);
      }
    };
    loadShowCalculated();
  }, [showCalculatedKey]);

const handleToggle = useCallback(async () => {
  if (isToggling) return; // Prevent multiple toggles
  
  const newValue = !isEnabled;
  
  logger.debug(Modules.PAGE_CLASS, `Toggle switch: ${isEnabled} -> ${newValue}`);
  
  setIsToggling(true);
  
  try {
    // Update UI state immediately for smooth animation
    setIsEnabled(newValue);
    
    // Save to storage in background
    await AsyncStorage.setItem(showCalculatedKey, newValue.toString());
    
    // Small delay to ensure smooth animation completion
    await new Promise(resolve => setTimeout(resolve, 100));
    
    logger.debug(Modules.PAGE_CLASS, 'Toggle completed successfully');
  } catch (error) {
    // If storage fails, revert the state
    console.error('Failed to toggle switch:', error);
    setIsEnabled(!newValue);
  } finally {
    setIsToggling(false);
  }
}, [isEnabled, isToggling, showCalculatedKey]);

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

  // Memoize the separator component
  const ItemSeparatorComponent = useCallback(() => <View className="h-4" />, []);

  // Memoize the renderItem function for better FlatList performance
  const renderAssignmentItem = useCallback(({ item, index }: { item: any; index: number }) => {
    const shouldShowSkeleton = loading || waitingForRetry || (apiAssignments.length > 0 && filteredAssignments.length === 0);
    
    return shouldShowSkeleton ? (
      <SkeletonAssignment key={`skeleton-${index}`} />
    ) : (
      <AssignmentCard
        {...(item as Assignment)}
        editing={!!isEnabled}
        classId={classId}
        corNumId={corNumId}
        section={section}
        gbId={gbId}
      />
    );
  }, [loading, waitingForRetry, apiAssignments.length, filteredAssignments.length, isEnabled, classId, corNumId, section, gbId]);

  // Memoize the key extractor
  const keyExtractor = useCallback((item: any, index: number) => {
    return loading || waitingForRetry || (apiAssignments.length > 0 && filteredAssignments.length === 0) 
      ? `skeleton-${index}` 
      : ((item as Assignment).id || `${(item as Assignment).className}-${(item as Assignment).name}-${(item as Assignment).term}-${(item as Assignment).dueDate}`);
  }, [loading, waitingForRetry, apiAssignments.length, filteredAssignments.length]);

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
          <TouchableWithoutFeedback onPress={() => {
            if (showFilterMenu) {
              toggleFilterMenu();
            }
          }}>
            <View>
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
                <Switch 
                  value={isEnabled} 
                  onValueChange={handleToggle}
                  disabled={isToggling}
                />
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
                from={{ opacity: 0, scale: 0.95, translateY: -10, height: 0, marginTop: 0 }}
                animate={{ opacity: 1, scale: 1, translateY: 0, height: 56, marginTop: 16 }}
                exit={{ opacity: 0, scale: 0.95, translateY: -10, height: 0, marginTop: 0 }}
                transition={{
                  type: "timing",
                  duration: 200,
                  easing: Easing.out(Easing.cubic),
                }}
                style={{ marginHorizontal: 16 }}
                pointerEvents={isEnabled ? "auto" : "none"}
              >
                <TouchableOpacity
                  onPress={handleResetArtificialAssignments}
                  className="bg-cardColor items-center rounded-lg py-3"
                >
                  <Text className="text-highlightText font-medium text-lg">Reset Assignments</Text>
                </TouchableOpacity>
              </MotiView>
            )}
          </AnimatePresence>
          
          {/* Filter Button */}
          <View className="px-5 mt-4 mb-2">
            <View className="flex-row items-center justify-between">
              <Text className="text-highlightText font-bold text-lg">Assignments</Text>
              <View className="relative">
                <TouchableOpacity
                  onPress={toggleFilterMenu}
                  className="bg-cardColor px-4 py-2 rounded-full flex-row items-center"
                >
                  <Ionicons 
                    name="filter-outline" 
                    size={16} 
                    color={theme === 'dark' ? '#ffffff' : '#000000'} 
                  />
                  <Text className="text-main text-sm font-medium ml-2 capitalize">
                    {sortOption} {sortOrder === 'asc' ? '↑' : '↓'}
                  </Text>
                </TouchableOpacity>
                
                {/* Filter Menu Popup */}
                {showFilterMenu && (
                  <AnimatedReanimated.View 
                    style={[
                      {
                        position: 'absolute',
                        top: 45,
                        right: 0,
                        backgroundColor: theme === 'dark' ? '#1f2937' : '#ffffff',
                        borderRadius: 12,
                        shadowColor: '#000',
                        shadowOffset: { width: 0, height: 4 },
                        shadowOpacity: 0.15,
                        shadowRadius: 12,
                        elevation: 8,
                        zIndex: 1000,
                        minWidth: 160,
                        borderWidth: 1,
                        borderColor: theme === 'dark' ? '#374151' : '#e5e7eb',
                      },
                      animatedFilterMenuStyle
                    ]}
                  >
                    <TouchableOpacity
                      onPress={() => handleSortChange('category')}
                      className="px-4 py-3 border-b border-gray-200 dark:border-gray-600"
                    >
                      <View className="flex-row items-center justify-between">
                        <Text className="text-main text-sm font-medium">Category A-Z</Text>
                        {sortOption === 'category' && (
                          <Ionicons 
                            name={sortOrder === 'asc' ? 'chevron-up' : 'chevron-down'} 
                            size={14} 
                            color={theme === 'dark' ? '#60a5fa' : '#2563eb'} 
                          />
                        )}
                      </View>
                    </TouchableOpacity>
                    
                    <TouchableOpacity
                      onPress={() => handleSortChange('date')}
                      className="px-4 py-3 border-b border-gray-200 dark:border-gray-600"
                    >
                      <View className="flex-row items-center justify-between">
                        <Text className="text-main text-sm font-medium">Date</Text>
                        {sortOption === 'date' && (
                          <Ionicons 
                            name={sortOrder === 'asc' ? 'chevron-up' : 'chevron-down'} 
                            size={14} 
                            color={theme === 'dark' ? '#60a5fa' : '#2563eb'} 
                          />
                        )}
                      </View>
                    </TouchableOpacity>
                    
                    <TouchableOpacity
                      onPress={() => handleSortChange('grade')}
                      className="px-4 py-3"
                    >
                      <View className="flex-row items-center justify-between">
                        <Text className="text-main text-sm font-medium">Highest Grade</Text>
                        {sortOption === 'grade' && (
                          <Ionicons 
                            name={sortOrder === 'asc' ? 'chevron-up' : 'chevron-down'} 
                            size={14} 
                            color={theme === 'dark' ? '#60a5fa' : '#2563eb'} 
                          />
                        )}
                      </View>
                    </TouchableOpacity>
                  </AnimatedReanimated.View>
                )}
              </View>
            </View>
          </View>

          <FlatList
            data={loading || waitingForRetry || (apiAssignments.length > 0 && filteredAssignments.length === 0) ? Array.from({ length: 8 }) : filteredAssignments}
            renderItem={renderAssignmentItem}
            keyExtractor={keyExtractor}
            className="mt-6 pb-8 px-3"
            scrollEnabled={false}
            ItemSeparatorComponent={ItemSeparatorComponent}
            removeClippedSubviews={true}
            maxToRenderPerBatch={10}
            windowSize={10}
            initialNumToRender={8}
            getItemLayout={(data, index) => ({
              length: 120, // Approximate height of AssignmentCard + separator
              offset: 124 * index, // height + separator
              index,
            })}
            ListEmptyComponent={
              loading || waitingForRetry || (apiAssignments.length > 0 && filteredAssignments.length === 0) ? null : (
                <View className="mt-10 px-5">
                  <Text className="text-center text-gray-500">No assignments found</Text>
                </View>
              )
            }
          />
            </View>
          </TouchableWithoutFeedback>
        </ScrollView>
      </View>
    </TouchableWithoutFeedback>
  );
};

export default React.memo(ClassDetails);