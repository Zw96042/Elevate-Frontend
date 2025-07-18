import { useState, useEffect, useCallback } from "react";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { useLocalSearchParams } from "expo-router";
import { useSharedValue, withTiming, runOnJS } from "react-native-reanimated";
import { calculateGradeSummary } from "@/utils/calculateGrades";
import formatClassName from "@/utils/formatClassName";

export function useClassDetails(selectedCategory: string) {
  const searchParams = useLocalSearchParams();
  const classParam = searchParams.class;
  const className = Array.isArray(classParam) ? classParam[0] : classParam;

  // Parse your term data similarly, but you could move this parsing into a helper util
  // ...

  const [isEnabled, setIsEnabled] = useState(false);
  const [isReady, setIsReady] = useState(false);
  const [displayGrade, setDisplayGrade] = useState(0);
  const animatedGrade = useSharedValue(0);

  const [filteredAssignments, setFilteredAssignments] = useState([]);
  const [courseSummary, setCourseSummary] = useState({
    courseTotal: "*",
    categories: {},
  });
  const [artificialAssignments, setArtificialAssignments] = useState([]);

  // Your fetchArtificialAssignments and related logic here...

  // Animated grade effect
  useEffect(() => {
    const value =
      courseSummary.courseTotal === "*" ? 100 : Number(courseSummary.courseTotal);
    animatedGrade.value = withTiming(value, { duration: 700 });
  }, [courseSummary.courseTotal]);

  // Reaction to update displayGrade from animated value...
  // Your animated reaction logic here...

  // Load isEnabled from AsyncStorage
  useEffect(() => {
    AsyncStorage.getItem("showCalculated").then((value) => {
      setIsEnabled(value === "true");
      setIsReady(true);
    });
  }, []);

  const handleToggle = async () => {
    const newValue = !isEnabled;
    setIsEnabled(newValue);
    await AsyncStorage.setItem("showCalculated", newValue.toString());
  };

  const handleResetArtificialAssignments = async () => {
    const data = await AsyncStorage.getItem("artificialAssignments");
    if (!data || !className) return;

    const parsed = JSON.parse(data);
    delete parsed[className];
    await AsyncStorage.setItem("artificialAssignments", JSON.stringify(parsed));
    // Re-fetch assignments
  };

  return {
    className,
    formattedName: formatClassName(className?.toString()),
    isEnabled,
    isReady,
    displayGrade,
    filteredAssignments,
    courseSummary,
    artificialAssignments,
    handleToggle,
    handleResetArtificialAssignments,
    animatedGrade,
    setFilteredAssignments,
    setArtificialAssignments,
    setCourseSummary,
    setIsEnabled,
  };
}