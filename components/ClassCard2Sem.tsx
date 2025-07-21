import { View, Text, TouchableOpacity, useColorScheme, DeviceEventEmitter } from 'react-native'
import React, { useEffect, useState } from 'react'
import { Link } from 'expo-router'
import formatClassName from '@/utils/formatClassName'
import PieChart from 'react-native-pie-chart'
import Animated, {
  useSharedValue,
  useAnimatedReaction,
  runOnJS,
  withTiming,
  Easing
} from 'react-native-reanimated'
import { Swipeable } from 'react-native-gesture-handler';
import AsyncStorage from '@react-native-async-storage/async-storage';

type TermLabel =
  | "Q1 Grades"
  | "Q2 Grades"
  | "SM1 Grade"
  | "Q3 Grades"
  | "Q4 Grades"
  | "SM2 Grades"

type TermData = {
  categories: {
    names: string[];
    weights: number[];
  };
  total: number;
};

// Props with term data for SM1 and SM2
const ClassCard2Sem = ({
  name,
  teacher,
  s1,
  s2,
  term,
  gradeLevel
}: {
  name: string,
  teacher: string,
  s1: TermData,
  s2: TermData,
  term: TermLabel,
  gradeLevel: string
}) => {
  const [displaySM1, setDisplaySM1] = useState(0)
  const [displaySM2, setDisplaySM2] = useState(0)

  const animatedSM1 = useSharedValue(0)
  const animatedSM2 = useSharedValue(0)

  useEffect(() => {
    const sm1Total = s1?.total ?? 0
    animatedSM1.value = withTiming(sm1Total, {
      duration: 700,
      easing: Easing.inOut(Easing.ease)
    })
  }, [s1])

  useEffect(() => {
    const sm2Total = s2?.total ?? 0
    animatedSM2.value = withTiming(sm2Total, {
      duration: 700,
      easing: Easing.inOut(Easing.ease)
    })
  }, [s2])

  useAnimatedReaction(
    () => animatedSM1.value,
    (value) => {
      runOnJS(setDisplaySM1)(value)
    }
  )

  useAnimatedReaction(
    () => animatedSM2.value,
    (value) => {
      runOnJS(setDisplaySM2)(value)
    }
  )

  const theme = useColorScheme()
  const highlightColor = theme === 'dark' ? '#3b5795' : '#a4bfed'
  const cardColor = theme === 'dark' ? '#1e293b' : '#fafafa'

  return (
    <Swipeable
      renderRightActions={() => (
        <TouchableOpacity
          className="bg-red-500 justify-center items-center px-4 mr-6 rounded-3xl h-20"
          onPress={async () => {
            const key = `savedClasses-${gradeLevel}`;
            const existingRaw = await AsyncStorage.getItem(key);
            const existing = existingRaw ? JSON.parse(existingRaw) : [];

            const updated = existing.filter((c: any) => c.className !== name);
            await AsyncStorage.setItem(key, JSON.stringify(updated));

            DeviceEventEmitter.emit('classDeleted');
          }}
        >
          <Text className="text-white font-bold">Delete</Text>
        </TouchableOpacity>
      )}
    >
      <View className='bg-bgColor mx-6'>
        <View className="w-full h-20 rounded-3xl bg-cardColor flex-row items-center justify-between px-5 mb-3">
          <View>
            <Text className="text-lg text-main font-normal">
              {name.length > 19 ? `${name.slice(0, 19).trim()}...` : name}
            </Text>
          </View>

          <View className="flex-row items-center">
            <View className="items-center mr-3">
              <View className="relative w-[50] h-[50]">
                <PieChart
                  widthAndHeight={50}
                  series={[
                    { value: Math.min(displaySM1, 100), color: highlightColor },
                    { value: 100 - Math.min(displaySM1, 100), color: cardColor }
                  ]}
                />
                <View className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 justify-center items-center">
                  <Text className="text-highlightText font-bold text-sm">
                    {displaySM1 === 0 ? '--' : `${displaySM1.toFixed(1)}%`}
                  </Text>
                </View>
              </View>
            </View>

            <View className="items-center">
              <View className="relative w-[50] h-[50]">
                <PieChart
                  widthAndHeight={50}
                  series={[
                    { value: Math.min(displaySM2, 100), color: highlightColor },
                    { value: 100 - Math.min(displaySM2, 100), color: cardColor }
                  ]}
                />
                <View className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 justify-center items-center">
                  <Text className="text-highlightText font-bold text-sm">
                    {displaySM2 === 0 ? '--' : `${displaySM2.toFixed(1)}%`}
                  </Text>
                </View>
              </View>
            </View>
          </View>
        </View>
      </View>
    </Swipeable>
  );
}

export default ClassCard2Sem