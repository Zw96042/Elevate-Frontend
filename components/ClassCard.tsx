import { View, Text, TouchableOpacity, useColorScheme, Pressable } from 'react-native'
import React, { useCallback, useEffect, useState, useMemo } from 'react'
import { Link, useFocusEffect } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';
import formatClassName from '@/utils/formatClassName';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { calculateGradeSummary } from '@/utils/calculateGrades';
import { generateUniqueId } from '@/utils/uniqueId';
import { useScreenDimensions } from '@/hooks/useScreenDimensions';
import PieChart from 'react-native-pie-chart'
import {
  useSharedValue,
  withTiming,
  useAnimatedReaction,
  runOnJS,
  Easing
} from 'react-native-reanimated';

type TermLabel =
  | "Q1 Grades"
  | "Q2 Grades"
  | "SM1 Grade"
  | "Q3 Grades"
  | "Q4 Grades"
  | "SM2 Grades";


// Course Name, Teacher Name, Numerical Grade
const ClassCard = ({ name, teacher, corNumId, stuId, section, gbId, t1, t2, s1, t3, t4, s2, term }: Class & { term: TermLabel }) => {
    const { height: screenHeight } = useScreenDimensions();
    
    const cardHeight = useMemo(() => {
        const responsiveHeight = Math.round(screenHeight * 0.0855);
        // Ensure minimum of 80px and maximum of 120px for usability
        return Math.max(72, Math.min(120, responsiveHeight));
    }, [screenHeight]);

    // Generate a truly unique identifier for this class instance
    const classId = useMemo(() => {
        return generateUniqueId();
    }, []); // Empty dependency array ensures this is truly unique per component instance

    const termMap: Record<TermLabel, TermData> = useMemo(() => ({
        "Q1 Grades": t1,
        "Q2 Grades": t2,
        "SM1 Grade": s1,
        "Q3 Grades": t3,
        "Q4 Grades": t4,
        "SM2 Grades": s2,
    }), [t1, t2, s1, t3, t4, s2]);

    type TermData = {
        categories: {
            names: string[];
            weights: number[];
        };
        total: number;
    };
    const currTerm = useMemo(() => termMap[term], [termMap, term]);

    // Memoize calculated values
    const percentage = useMemo(() => currTerm.total, [currTerm.total]);
    const letter = useMemo(() => 
      percentage >= 90 ? "A" : percentage >= 80 ? "B" : percentage >= 70 ? "C" : "D", 
      [percentage]);
    const bgColor = useMemo(() => "bg-highlight", []);

    const [isEnabled, setIsEnabled] = useState(false);

  

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

    const [displayGrade, setDisplayGrade] = useState(0);

    const animatedGrade = useSharedValue(0);

    const fetchArtificialAssignments = useCallback(async () => {
      if (!name) return;
      const data = await AsyncStorage.getItem("artificialAssignments");
      let all: Assignment[] = [];
      if (data) {
        const parsed = JSON.parse(data);
        
        // For SM1/SM2, check both constituent terms and the semester term
        const termsToCheck = [term.split(" ")[0]]; // Start with the base term
        if (term === "SM1 Grade") {
          termsToCheck.push("Q1", "Q2", "SM1");
        } else if (term === "SM2 Grades") {
          termsToCheck.push("Q3", "Q4", "SM2");
        }
        
        let allAssignments: Assignment[] = [];
        termsToCheck.forEach(termKey => {
          const storageKey = `${name}_${corNumId}_${section}_${gbId}_${termKey}`;
          const classAssignments = parsed[storageKey] ?? [];
          allAssignments = [...allAssignments, ...classAssignments];
          
          // Also check old format for backward compatibility
          if (termKey === term.split(" ")[0]) {
            const oldStorageKey = `${name}_${corNumId}_${section}_${gbId}_${term}`;
            const oldAssignments = parsed[oldStorageKey] ?? [];
            allAssignments = [...allAssignments, ...oldAssignments];
          }
        });
        
        const artificial = isEnabled ? allAssignments : [];
        all = artificial.filter((a: { grade: string; }) => a.grade !== '*');
      }
      // If no artificial assignments, just set empty summary
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
      setCourseSummary(calculateGradeSummary(all, normalizedWeights));
    }, [name, term, isEnabled, currTerm.categories.names, currTerm.categories.weights, classId]);

  useFocusEffect(
    useCallback(() => {
      const loadShowCalculated = async () => {
        const value = await AsyncStorage.getItem('showCalculated');
        if (value !== null) {
          setIsEnabled(value === 'true');
        }
      };
      loadShowCalculated();
    }, [])
  );

  useEffect(() => {
    fetchArtificialAssignments();
  }, [fetchArtificialAssignments]);

  useEffect(() => {
    const value = currTerm.total > 0 
      ? currTerm.total 
      : courseSummary.courseTotal === '*'
        ? 100
        : Number(courseSummary.courseTotal);
    animatedGrade.value = withTiming(value, {
      duration: 700,
      easing: Easing.inOut(Easing.ease)
    });
  }, [currTerm.total, courseSummary.courseTotal]);

  useFocusEffect(
    useCallback(() => {
      fetchArtificialAssignments();
    }, [fetchArtificialAssignments])
  );

  const theme = useColorScheme();
  
  // Memoize theme colors
  const themeColors = useMemo(() => ({
    highlightColor: theme === 'dark' ? '#3b5795' : "#a4bfed",
    cardColor: theme === 'dark' ? '#1e293b' : "#fafafa"
  }), [theme]);

  const { highlightColor, cardColor } = themeColors;

  useAnimatedReaction(
    () => animatedGrade.value,
    (currentValue) => {
      runOnJS(setDisplayGrade)(currentValue);
    }
  );

  return (
    
    <Link 
        href={{
            pathname: '/classes/[class]',
            params: {
                classId: classId,
                class: name,
                teacher: teacher,
                corNumId: corNumId,
                stuId: stuId,
                section: section,
                gbId: gbId,
                t1: JSON.stringify(t1),
                t2: JSON.stringify(t2),
                s1: JSON.stringify(s1),
                t3: JSON.stringify(t3),
                t4: JSON.stringify(t4),
                s2: JSON.stringify(s2),
                term
            }
        }}
        asChild
    >
        <TouchableOpacity className='w-[100%]'>
            <View 
                className='w-full rounded-3xl bg-cardColor flex-row items-center justify-between'
                style={{ height: cardHeight }}
            >
                <View>
                    <Text className='text-lg text-main font-normal ml-5'>{formatClassName(name)}</Text>
                    <Text className='text-sm text-secondary ml-5'>{formatClassName(teacher) }</Text>
                </View>
                <View className="flex-row items-center gap-4">
                    <View className="items-center w-3 mr-4">
                        <View className="relative w-[50] h-[50]">
                          <PieChart
                            widthAndHeight={50}
                            series={[
                              { value: Math.min(displayGrade, 100), color: highlightColor },
                              { value: 100 - Math.min(displayGrade, 100), color: cardColor },
                            ]}
                          />
                          <View className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 justify-center items-center">
                            <Text className="text-highlightText font-bold text-sm">
                              {currTerm.total > 0
                                ? currTerm.total === 100
                                  ? '100%'
                                  : `${currTerm.total.toFixed(0)}%`
                                : courseSummary.courseTotal === '*'
                                ? '--'
                                : Number(courseSummary.courseTotal) === 100
                                ? '100%'
                                : `${Number(courseSummary.courseTotal).toFixed(0)}%`}
                            </Text>
                          </View>
                        </View>
                        
                    </View>

                    {/* <View className='mr-3'></View> */}
                    <Ionicons name="chevron-forward" size={24} color="#cbd5e1" className='mr-3'/>
                    {/* <View className='w-[24px] h-[24px]'></View> */}
                </View>
            </View>
        </TouchableOpacity>
    </Link>
  )
}

export default ClassCard