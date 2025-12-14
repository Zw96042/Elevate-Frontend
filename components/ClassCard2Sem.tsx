import { View, Text, TouchableOpacity, useColorScheme, DeviceEventEmitter } from 'react-native'
import React, { useEffect, useState, useMemo } from 'react'
import { Link } from 'expo-router'
import formatClassName from '@/utils/formatClassName'
import { useScreenDimensions } from '@/hooks/useScreenDimensions'
import PieChart from 'react-native-pie-chart'
import Swipeable from 'react-native-gesture-handler/Swipeable';
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

type CourseLevel = "AP" | "Honors" | "Regular";

// Props with term data for SM1 and SM2
const ClassCard2Sem = ({
  name,
  teacher,
  s1,
  s2,
  term,
  gradeLevel,
  courseLevel,
  showDeleteAction = true,
  termLabels = { s1: "SM1", s2: "SM2" }
}: {
  name: string,
  teacher: string,
  s1: TermData,
  s2: TermData,
  term: TermLabel,
  gradeLevel: string,
  courseLevel?: CourseLevel,
  showDeleteAction?: boolean,
  termLabels?: { s1: string, s2: string }
}) => {
  const { height: screenHeight } = useScreenDimensions();
  
  // Calculate responsive height (approximately 10% of screen height, with min/max bounds)
  const cardHeight = useMemo(() => {
    const responsiveHeight = Math.round(screenHeight * 0.10);
    // Ensure minimum of 80px and maximum of 110px for usability
    return Math.max(80, Math.min(110, responsiveHeight));
  }, [screenHeight]);

  const [displaySM1, setDisplaySM1] = useState(0)
  const [displaySM2, setDisplaySM2] = useState(0)

  useEffect(() => {
    // console.log('[ClassCard2Sem] s1.total:', s1?.total);
    let sm1Total = 0;
    if (typeof s1?.total === 'string') {
      sm1Total = s1.total === '' ? -1 : Number(s1.total);
    } else if (typeof s1?.total === 'number') {
      sm1Total = s1.total;
    }
    setDisplaySM1(sm1Total);
  }, [s1]);

  useEffect(() => {
    // console.log('[ClassCard2Sem] s2.total:', s2?.total);
    let sm2Total = 0;
    if (typeof s2?.total === 'string') {
      sm2Total = s2.total === '' ? -1 : Number(s2.total);
    } else if (typeof s2?.total === 'number') {
      sm2Total = s2.total;
    }
    setDisplaySM2(sm2Total);
  }, [s2]);

  const theme = useColorScheme()
  const highlightColor = theme === 'dark' ? '#3b5795' : '#a4bfed'
  const cardColor = theme === 'dark' ? '#1e293b' : '#fafafa'

  // Get badge color based on course level
  const getBadgeColor = () => {
    switch (courseLevel) {
      case "AP": return "bg-purple-600";
      case "Honors": return "bg-blue-600";
      case "Regular": return "bg-gray-600";
      default: return "bg-gray-600";
    }
  };

  const cardContent = (
    <View className='bg-bgColor mx-6'>
      <View 
        className="w-full rounded-3xl bg-cardColor flex-row items-center justify-between px-5 mb-3"
        style={{ height: cardHeight }}
      >
        <View className="flex-1 mr-3">
          {courseLevel != "Regular" && (
            <View className={`self-start rounded-md bg-highlight px-2`}>
              <Text className="text-sm text-highlightText font-bold">{courseLevel}</Text>
            </View>
          )}
          <Text className="text-lg text-main font-normal">
            {(() => {
              const stripped = formatClassName(name.split(' - ')[0].replaceAll(" ", "_").split(":")[0]);
              return stripped.length > 26 ? `${stripped.slice(0, 26).trim()}...` : stripped;
            })()}
          </Text>
          
        </View>

        <View className="flex-col items-center justify-center space-y-1">
          <View className="items-center flex-row mb-2">
            <Text className="text-xs text-main">{termLabels.s1}:</Text>
            <Text className="text-highlightText font-bold text-sm ml-1">
              {displaySM1 === -1 ? '--' : `${displaySM1.toFixed(1)}%`}
            </Text>
          </View>
          <View className="items-center flex-row">
            <Text className="text-xs text-main">{termLabels.s2}:</Text>
            <Text className="text-highlightText font-bold text-sm ml-1">
              {displaySM2 === -1 ? '--' : `${displaySM2.toFixed(1)}%`}
            </Text>
          </View>
        </View>
      </View>
    </View>
  );

  if (!showDeleteAction) {
    return cardContent;
  }

  return (
    <Swipeable
      renderRightActions={() => (
        <TouchableOpacity
          className="bg-red-500 justify-center items-center px-4 mr-6 rounded-3xl"
          style={{ height: cardHeight }}
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
      {cardContent}
    </Swipeable>
  );
}

export default ClassCard2Sem