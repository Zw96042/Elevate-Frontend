import { View, Text, TouchableOpacity, useColorScheme } from 'react-native'
import React, { useCallback, useEffect, useState } from 'react'
import { Link, useFocusEffect } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';
import formatClassName from '@/utils/formatClassName';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { ASSIN } from '@/app/classes/[class]';
import { calculateGradeSummary } from '@/utils/calculateGrades';
import PieChart from 'react-native-pie-chart'
import Animated, {
  useSharedValue,
  useAnimatedProps,
  withTiming,
  useDerivedValue,
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
const ClassCard = ({ name, teacher, t1, t2, s1, t3, t4, s2, term }: Class & { term: TermLabel }) => {
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
    const currTerm = termMap[term];

    // const { class: classParam, teacher, t1, t2, s1, t3, t4, s2, term } = useLocalSearchParams();
    
    const percentage = currTerm.total;
    const letter = percentage >= 90 ? "A" : percentage >= 80 ? "B" : percentage >= 70 ? "C" : "D";
    let bgColor = "bg-highlight";
    // if (letter === "B") bgColor = "bg-yellow-400";
    // else if (letter === "C" || letter === "D") bgColor = "bg-red-300";

    const [isEnabled, setIsEnabled] = useState(false);

    const [artificialAssignments, setArtificialAssignments] = useState<Assignment[]>([]);

    const [filteredAssignments, setFilteredAssignments] = useState<Assignment[]>(() => {
      if (!name || !term) return [];
      return ASSIN.filter(
        (item) =>
          item.className === name &&
          item.term === term.split(" ")[0] &&
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

    const [displayGrade, setDisplayGrade] = useState(0);

    const animatedGrade = useSharedValue(0);

    const fetchArtificialAssignments = useCallback(async () => {
      if (!name) return;

      // await AsyncStorage.clear();
      const data = await AsyncStorage.getItem("artificialAssignments");
      if (!data) {
        const real = ASSIN.filter(
          (item) => item.className === name && item.term === term.split(" ")[0]
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
      const classAssignments = parsed[name] ?? [];
      setArtificialAssignments(classAssignments);

      const real = ASSIN.filter(
        (item) => item.className === name && item.term === term.split(" ")[0]
      );

      const artificial = isEnabled
        ? classAssignments.filter(
            (item: Assignment) =>
              item.className === name && item.term === term.split(" ")[0]
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
    }, [name, term, isEnabled, currTerm.categories.names, currTerm.categories.weights]);

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
    const value =
      courseSummary.courseTotal === '*'
        ? 100
        : Number(courseSummary.courseTotal);
    animatedGrade.value = withTiming(value, {
      duration: 700,
      easing: Easing.inOut(Easing.ease)
    });
  }, [courseSummary.courseTotal]);

  useFocusEffect(
    useCallback(() => {
      fetchArtificialAssignments();
    }, [fetchArtificialAssignments])
  );

  const theme = useColorScheme();
  const highlightColor = theme === 'dark' ? '#3b5795' : "#a4bfed";
  const cardColor = theme === 'dark' ? '#1e293b' : "#fafafa";

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
                class: name,
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
        <TouchableOpacity  className='w-[100%]'>
            <View className='w-full h-28 rounded-3xl bg-cardColor flex-row items-center justify-between'>
                <View>
                    <Text className='text-lg text-main font-normal ml-5'>{formatClassName(name)}</Text>
                    <Text className='text-sm text-secondary ml-5'>{formatClassName(teacher)}</Text>
                </View>
                <View className="flex-row items-center gap-4">
                    {/* <View className="items-center">
                        <View className={`w-10 h-10 rounded-full ${bgColor} items-center justify-center`}>
                            <Text className="text-white font-semibold">{letter}</Text>
                        </View>
                        <Text className="text-xs text-main mt-1">{percentage.toFixed(1)}%</Text>
                    </View> */}
                    <View className="items-center w-3 mr-4">
                        <View className="relative w-[50] h-[50]">
                          <PieChart
                            widthAndHeight={50}
                            series={[
                              { value: displayGrade, color: highlightColor },
                              { value: 100 - displayGrade, color: cardColor },
                            ]}
                          />
                          <View className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 justify-center items-center">
                            <Text className="text-highlightText font-bold text-sm">
                              {courseSummary.courseTotal === '*'
                                ? '--'
                                : Number(courseSummary.courseTotal) === 100
                                ? '100%'
                                : `${Number(courseSummary.courseTotal).toFixed(1)}%`}
                            </Text>
                          </View>
                        </View>
                        
                    </View>

                    <Ionicons name="chevron-forward" size={24} color="#cbd5e1" className='mr-3'/>
                </View>
            </View>
        </TouchableOpacity>
    </Link>
  )
}

export default ClassCard