import {
  View,
  Text,
  TouchableOpacity,
  Keyboard,
  TouchableWithoutFeedback,
  Switch,
  useColorScheme,
  RefreshControl,
} from "react-native";
import {
  useSharedValue,
  useAnimatedReaction,
  withTiming,
  runOnJS,
  Easing,
} from 'react-native-reanimated';
import React, {
  useEffect,
  useState,
  useCallback,
  useLayoutEffect,
  useMemo,
} from "react";
import { useFocusEffect, useNavigation } from "@react-navigation/native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { Stack, useLocalSearchParams } from "expo-router";
import formatClassName from "@/utils/formatClassName";
import { calculateGradeSummary } from "@/utils/calculateGrades";
import { ensureUniqueAssignmentIds } from "@/utils/uniqueId";
import AssignmentCard from "@/components/AssignmentCard";
import { useAddAssignmentSheet } from "@/context/AddAssignmentSheetContext";
import { useBottomSheet } from "@/context/BottomSheetContext";
import PieChart from "react-native-pie-chart";
import { DataService } from '@/lib/services';
import { logger, Modules } from '@/lib/utils/logger';
import { ScrollView } from "react-native-gesture-handler";
import SkeletonAssignment from '@/components/SkeletonAssignment';
import { SymbolView } from "expo-symbols";
import * as Burnt from "burnt";
import FilterButton from '@/components/FilterButton';
import { useFilter } from '@/context/FilterContext';
import { padding } from "@expo/ui/swift-ui/modifiers";
import { Button, Host } from "@expo/ui/swift-ui";

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
  
  // Memoize current term to prevent unnecessary recalculations
  const currTerm = useMemo(() => termMap[selectedCategory], [termMap, selectedCategory]);
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
  const [apiCategories, setApiCategories] = useState<{ names: string[]; weights: number[] }>({ names: [], weights: [] });
  const [apiAssignments, setApiAssignments] = useState<Assignment[]>([]);
  const [lastFetchTime, setLastFetchTime] = useState<number>(0);
  const [refreshing, setRefreshing] = useState<boolean>(false);
  const CACHE_DURATION = 10 * 60 * 1000; // 10 minutes
  
  // Track category changes for refresh logic
  const [previousSelectedCategory, setPreviousSelectedCategory] = useState<TermLabel | null>(null);

  // Use filter context instead of local state
  const {
    sortOption,
    sortOrder,
    selectedCategories,
    selectedAssignmentTypes,
    setAvailableCategories,
    handleSortChange: contextHandleSortChange
  } = useFilter();

  // Sort and filter assignments function
  const sortAndFilterAssignments = useCallback((assignments: Assignment[], sortBy: 'Category' | 'Date' | 'Grade', order: 'asc' | 'desc', categoryFilters: string[], assignmentTypeFilters: string[] = []) => {
    // First filter by categories if any are selected
    let filtered = assignments;
    if (categoryFilters.length > 0) {
      filtered = assignments.filter(assignment => categoryFilters.includes(assignment.category));
    }
    
    // Then filter by assignment types if any are selected
    if (assignmentTypeFilters.length > 0) {
      filtered = filtered.filter(assignment => {
        // If no meta data, include assignment (it's not missing, absent, or no count)
        if (!assignment.meta || assignment.meta.length === 0) {
          return false; // Only show assignments that match the selected types
        }
        
        // Check if assignment has any of the selected meta types
        return assignment.meta.some(meta => assignmentTypeFilters.includes(meta.type));
      });
    }
    
    // Then sort the filtered results
    return [...filtered].sort((a, b) => {
      let comparison = 0;
      
      switch (sortBy) {
        case 'Category':
          comparison = a.category.localeCompare(b.category);
          break;
        case 'Date':
          const parseDate = (date: string) => {
            const [month, day, year] = date.split('/').map(Number);
            return new Date(year < 100 ? 2000 + year : year, month - 1, day);
          };
          comparison = parseDate(a.dueDate).getTime() - parseDate(b.dueDate).getTime(); // asc = oldest first, desc = recent first
          break;
        case 'Grade':
          const gradeA = a.grade === '*' ? -1 : parseFloat(a.grade) || 0;
          const gradeB = b.grade === '*' ? -1 : parseFloat(b.grade) || 0;
          comparison = gradeA - gradeB;
          break;
      }
      
      return order === 'asc' ? comparison : -comparison;
    });
  }, []);



  // Use context handleSortChange
  const handleSortChange = contextHandleSortChange;

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

  // Memoize the mesh assignments function to prevent unnecessary recalculations
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
      
      // Update available categories for filtering
      const categories = [...new Set(realWithIds.map(a => a.category))];
      setAvailableCategories(categories);
      
      const sortedAssignments = sortAndFilterAssignments(realWithIds, sortOption, sortOrder, selectedCategories, selectedAssignmentTypes);
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
      setCourseSummary(calculateGradeSummary(all, normalizedWeights, termMap, selectedCategory));
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
    
    // Update available categories for filtering
    const categories = [...new Set(assignmentsWithIds.map(a => a.category))];
    setAvailableCategories(categories);
    
    const sortedAssignments = sortAndFilterAssignments(assignmentsWithIds, sortOption, sortOrder, selectedCategories, selectedAssignmentTypes);
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
    const newCourseSummary = calculateGradeSummary(all, normalizedWeights, termMap, selectedCategory);
    logger.debug(Modules.PAGE_CLASS, `Setting course summary: ${newCourseSummary.courseTotal} (isEnabled: ${isEnabled}, assignments: ${all.length})`);
    setCourseSummary(newCourseSummary);
  }, [apiAssignments, apiCategories, isEnabled, selectedCategory, className, corNumId, section, gbId, sortAndFilterAssignments, setAvailableCategories]);


  // Memoize the grade value calculation to prevent unnecessary recalculations
  const gradeValue = useMemo(() => {
    if (courseSummary.courseTotal === '*') {
      if (currTerm.total === "--" || currTerm.total === undefined || currTerm.total === null) {
        return 100;
      } else {
        return Number(currTerm.total);
      }
    } else {
      return Number(courseSummary.courseTotal);
    }
  }, [courseSummary.courseTotal, currTerm.total]);

  useEffect(() => {
    // Don't update grade during toggle to prevent jittery animation
    if (isToggling) return;
    
    logger.debug(Modules.PAGE_CLASS, `Grade calculation: courseSummary.courseTotal=${courseSummary.courseTotal}, currTerm.total=${currTerm.total}, finalValue=${gradeValue}, isEnabled=${isEnabled}`);
    
    // Check if the jump is too large (50+ points) to skip animation
    const currentValue = animatedGrade.value;
    const difference = Math.abs(gradeValue - currentValue);
    
    if (difference >= 50) {
      // Skip animation for large jumps
      animatedGrade.value = gradeValue;
    } else {
      // Normal animation for smaller changes - use proper timing
      animatedGrade.value = withTiming(gradeValue, {
        duration: 600,
        easing: Easing.out(Easing.quad),
      });
    }
  }, [gradeValue, isEnabled, isToggling, animatedGrade]);

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

  // Separate effect for handling filter changes without re-meshing assignments
  useEffect(() => {
    if (apiAssignments.length > 0 || artificialAssignments.length > 0) {
      // Re-apply sorting and filtering when filter options change
      const allAssignments = [...artificialAssignments, ...apiAssignments.filter(api => 
        !artificialAssignments.some(art => art.name === api.name)
      )];
      
      if (allAssignments.length > 0) {
        const assignmentsWithIds = ensureUniqueAssignmentIds(allAssignments);
        const sortedAssignments = sortAndFilterAssignments(assignmentsWithIds, sortOption, sortOrder, selectedCategories, selectedAssignmentTypes);
        setFilteredAssignments(sortedAssignments);
      }
    }
  }, [sortOption, sortOrder, selectedCategories, selectedAssignmentTypes, apiAssignments, artificialAssignments, sortAndFilterAssignments]);

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
        
        // Update available categories for filtering
        const categories = [...new Set(realWithIds.map(a => a.category))];
        setAvailableCategories(categories);
        
        const sortedAssignments = sortAndFilterAssignments(realWithIds, sortOption, sortOrder, selectedCategories, selectedAssignmentTypes);
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
    
    // Update available categories for filtering
    const categories = [...new Set(assignmentsWithIds.map(a => a.category))];
    setAvailableCategories(categories);
    
    const sortedAssignments = sortAndFilterAssignments(assignmentsWithIds, sortOption, sortOrder, selectedCategories, selectedAssignmentTypes);
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
    setCourseSummary(calculateGradeSummary(all, normalizedWeights, termMap, selectedCategory));
  }, [apiAssignments, apiCategories, isEnabled, selectedCategory, className, corNumId, section, gbId, sortAndFilterAssignments, setAvailableCategories]);

  useFocusEffect(
    React.useCallback(() => {
      refreshArtificialAssignmentsOnFocus();
    }, [refreshArtificialAssignmentsOnFocus])
  );

  const { openModal } = useAddAssignmentSheet();

  

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
    Burnt.toast({
      title: "Reset the assignments",
     
      duration: 1,
      preset: 'done',
      haptic: 'success',
    });
    
    setArtificialAssignments(prev => prev.filter(assignment =>
      !termsToReset.includes(assignment.term as TermLabel)
    ));

    meshAssignments();
  };

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => {
        if (!isEnabled) {
          return null;
        }
        
        return (
          <View className="flex-row items-center">
            <View className="flex-row items-center rounded-full overflow-hidden">
              {/* Add */}
              <TouchableOpacity
                className="pr-2 pl-[0.625rem] py-2"
                onPress={async () => {
                  openModal({
                    className: className || "",
                    classId,
                    corNumId,
                    section,
                    gbId,
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
                hitSlop={0}
              >
                <SymbolView size={20} name="plus" />
              </TouchableOpacity>

              {apiCategories.names.length > 0 && (
                <TouchableOpacity
                  className="px-2 py-2"
                  onPress={handleResetArtificialAssignments}
                  hitSlop={0}
                >
                  <SymbolView
                    size={20}
                    name="arrow.counterclockwise"
                  />
                </TouchableOpacity>
              )}
            </View>
          </View>
        );
      },
    });
  }, [
    navigation,
    isEnabled,
    apiCategories.names.length,
    openModal,
    handleResetArtificialAssignments,
    className,
    classId,
    selectedCategory,
    artificialAssignments,
    setArtificialAssignments,
    setFilteredAssignments,
    calculateGradeSummary,
    meshAssignments,
  ]);


  // Memoize the key extractor
  const keyExtractor = useCallback((item: any, index: number) => {
    // Handle skeleton items (undefined) or loading states
    if (loading || waitingForRetry || !item) {
      return `skeleton-${index}`;
    }
    
    // Handle actual assignment items
    const assignment = item as Assignment;
    return assignment.id || `${assignment.className}-${assignment.name}-${assignment.term}-${assignment.dueDate}`;
  }, [loading, waitingForRetry]);

  // Memoize the FlatList data to prevent unnecessary re-renders
  const flatListData = useMemo(() => {
    if (loading || waitingForRetry) {
      return Array.from({ length: 8 }); // Show skeletons when loading
    }
    
    // If we have API assignments but no filtered assignments, check if it's due to filters
    if (apiAssignments.length > 0 && filteredAssignments.length === 0) {
      const hasActiveFilters = selectedCategories.length > 0 || selectedAssignmentTypes.length > 0;
      if (hasActiveFilters) {
        return []; // No results due to filters - show empty state
      } else {
        return Array.from({ length: 8 }); // Still loading/processing - show skeletons
      }
    }
    
    return filteredAssignments;
  }, [loading, waitingForRetry, apiAssignments.length, filteredAssignments, selectedCategories.length, selectedAssignmentTypes.length]);

  // Get theme and memoize theme colors
  const theme = useColorScheme();
  const themeColors = useMemo(() => ({
    highlightColor: theme === 'dark' ? '#3b5795' : "#a4bfed",
    backgroundColor: theme === 'dark' ? '#030014' : "#ffffff",
    indicatorColor: theme === 'dark' ? '#ffffff' : '#000000'
  }), [theme]);

  const { highlightColor, backgroundColor, indicatorColor } = themeColors;

  // Memoize the grade display section (doesn't depend on isEnabled)
  const GradeDisplaySection = useMemo(() => (
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
  ), [displayGrade, highlightColor, backgroundColor, courseSummary.courseTotal, currTerm.total, selectedCategory, bottomSheetRef]);

  // Memoize the categories section (depends on isEnabled but only for visibility)
  const CategoriesSection = useMemo(() => {
    if (loading || apiCategories.names.length === 0) return null;
    
    return (
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
    );
  }, [loading, apiCategories.names, apiCategories.weights, courseSummary.categories, isEnabled, handleToggle, isToggling]);

  // Memoize the reset button section (only depends on isEnabled for visibility)
  

  // Simplified assignments section header with filter button
  const AssignmentsSection = useMemo(() => (
    <View className="px-5 mt-4 mb-2">
      <View className="flex-row items-center justify-between">
        <Text className="text-highlightText font-bold text-lg">Assignments</Text>
        <FilterButton availableCategories={apiCategories.names} />
      </View>
    </View>
  ), [apiCategories.names]);





  // console.log(filteredAssignments);
  return (
    <TouchableWithoutFeedback onPress={Keyboard.dismiss} accessible={false}>
      <View className="bg-primary flex-1 overflow-visible">
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
          showsVerticalScrollIndicator={true}
          contentContainerStyle={{ 
            paddingBottom: 0, // Increased bottom padding
            flexGrow: 1
          }}
        >
          {GradeDisplaySection}
          {CategoriesSection}
          {/* {ResetButtonSection} */}
          {AssignmentsSection}

          <View className="mt-2 px-3 pb-20">
            {flatListData.length === 0 && !loading && !waitingForRetry ? (
              // Show "no results" message when filters don't match anything
              <View className="mt-10 px-5">
                <View className="items-center">
                  <SymbolView
                    name="magnifyingglass"
                    size={48}
                    type="hierarchical"
                    tintColor="#9CA3AF"
                    className="mb-4"
                  />
                  <Text className="text-center text-gray-500 text-lg font-medium mb-2">
                    No assignments found
                  </Text>
                  <Text className="text-center text-gray-400 text-sm">
                    {(selectedCategories.length > 0 || selectedAssignmentTypes.length > 0) 
                      ? "Try adjusting your filters to see more results"
                      : "No assignments available for this term"
                    }
                  </Text>
                </View>
              </View>
            ) : (
              flatListData.map((item, index) => {
                const shouldShowSkeleton = loading || waitingForRetry || !item;
                
                return (
                  <View key={keyExtractor(item, index)}>
                    {shouldShowSkeleton ? (
                      <SkeletonAssignment />
                    ) : (
                      <AssignmentCard
                        {...(item as Assignment)}
                        editing={!!isEnabled}
                        classId={classId}
                        corNumId={corNumId}
                        section={section}
                        gbId={gbId}
                      />
                    )}
                    {index < flatListData.length - 1 && <View className="h-4" />}
                  </View>
                );
              })
            )}
          </View>
        </ScrollView>
        {/* {isEnabled && apiCategories.names.length > 0 && (
  <View className="absolute bottom-0 left-0 right-0 px-4 pb-6">
    <View className="bg-[#1e293b]/80 backdrop-blur-xl  rounded-2xl opacity-80">
      <TouchableOpacity
        onPress={handleResetArtificialAssignments}
        className="py-4 items-center"
      >
        <Text className="text-highlightText font-semibold text-lg">
          Reset Assignments
        </Text>
      </TouchableOpacity>
    </View>
  </View>
)} */}
      </View>
    </TouchableWithoutFeedback>
  );
};

export default React.memo(ClassDetails);