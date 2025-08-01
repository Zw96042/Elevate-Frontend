import { View, Text, TouchableOpacity, useColorScheme, DeviceEventEmitter } from 'react-native'
import React, { useEffect, useState } from 'react'
import { Link } from 'expo-router'
import formatClassName from '@/utils/formatClassName'
import PieChart from 'react-native-pie-chart'
import Swipeable from 'react-native-gesture-handler/ReanimatedSwipeable';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { MotiView } from 'moti'

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

  useEffect(() => {
    const sm1Total = typeof s1?.total === 'number' ? s1.total : 0;
    setDisplaySM1(sm1Total);
  }, [s1]);

  useEffect(() => {
    const sm2Total = typeof s2?.total === 'number' ? s2.total : 0;
    setDisplaySM2(sm2Total);
  }, [s2]);

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
              {(() => {
                const stripped = formatClassName(name.split(' - ')[0].replaceAll(" ", "_").split(":")[0]);
                return stripped.length > 27 ? `${stripped.slice(0, 27).trim()}...` : stripped;
              })()}
            </Text>
          </View>

          <View className="flex-col items-center justify-center space-y-1">
            <View className="items-center flex-row mb-2">
              <Text className="text-xs text-main">SM1:</Text>
              <Text className="text-highlightText font-bold text-sm">
                {displaySM1 === -1 ? '--' : `${displaySM1.toFixed(1)}%`}
              </Text>
            </View>
            <View className="items-center flex-row">
              <Text className="text-xs text-main">SM2:</Text>
              <Text className="text-highlightText font-bold text-sm">
                {displaySM2 === -1 ? '--' : `${displaySM2.toFixed(1)}%`}
              </Text>
            </View>
          </View>
        </View>
      </View>
    </Swipeable>
  );
}

export default ClassCard2Sem