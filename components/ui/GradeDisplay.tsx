/**
 * Grade Display Component
 * Handles animated grade display and pie charts
 */

import React, { useEffect, useState } from 'react';
import { View, Text, useColorScheme } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedReaction,
  withTiming,
  runOnJS,
  Easing,
} from 'react-native-reanimated';

interface GradeDisplayProps {
  grade: number;
  letter: string;
  animated?: boolean;
  showPieChart?: boolean;
  size?: 'small' | 'medium' | 'large';
}

export const GradeDisplay: React.FC<GradeDisplayProps> = ({
  grade,
  letter,
  animated = true,
  showPieChart = true,
  size = 'medium',
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';
  
  const [displayGrade, setDisplayGrade] = useState(0);
  const animatedGrade = useSharedValue(0);

  const getSizeConfig = () => {
    switch (size) {
      case 'small':
        return { chartSize: 80, fontSize: 20, containerSize: 100 };
      case 'large':
        return { chartSize: 120, fontSize: 32, containerSize: 140 };
      default:
        return { chartSize: 100, fontSize: 28, containerSize: 120 };
    }
  };

  const { chartSize, fontSize, containerSize } = getSizeConfig();

  useEffect(() => {
    if (animated) {
      animatedGrade.value = withTiming(grade, {
        duration: 1000,
        easing: Easing.out(Easing.quad),
      });
    } else {
      setDisplayGrade(grade);
    }
  }, [grade, animated]);

  useAnimatedReaction(
    () => animatedGrade.value,
    (currentValue: number) => {
      runOnJS(setDisplayGrade)(Math.round(currentValue));
    }
  );

  const getGradeColor = () => {
    if (grade >= 90) return '#4ade80'; // Green
    if (grade >= 80) return '#fbbf24'; // Yellow
    if (grade >= 70) return '#fb923c'; // Orange
    return '#ef4444'; // Red
  };

  const getBackgroundColor = () => {
    if (isDark) return '#374151';
    return '#f3f4f6';
  };

  if (!showPieChart) {
    return (
      <View style={{
        alignItems: 'center',
        justifyContent: 'center',
        width: containerSize,
        height: containerSize,
        backgroundColor: getBackgroundColor(),
        borderRadius: containerSize / 2,
      }}>
        <Text style={{
          fontSize: fontSize,
          fontWeight: 'bold',
          color: getGradeColor(),
        }}>
          {displayGrade}%
        </Text>
        <Text style={{
          fontSize: fontSize * 0.6,
          fontWeight: '600',
          color: isDark ? '#d1d5db' : '#6b7280',
        }}>
          {letter}
        </Text>
      </View>
    );
  }

  return (
    <View style={{
      alignItems: 'center',
      justifyContent: 'center',
      position: 'relative',
    }}>
      {/* Simplified circular progress - can be enhanced with custom drawing or SVG */}
      <View style={{
        width: chartSize,
        height: chartSize,
        borderRadius: chartSize / 2,
        backgroundColor: getBackgroundColor(),
        borderWidth: 8,
        borderColor: getGradeColor(),
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        <Text style={{
          fontSize: fontSize,
          fontWeight: 'bold',
          color: getGradeColor(),
        }}>
          {displayGrade}%
        </Text>
        <Text style={{
          fontSize: fontSize * 0.5,
          fontWeight: '600',
          color: isDark ? '#d1d5db' : '#6b7280',
        }}>
          {letter}
        </Text>
      </View>
    </View>
  );
};
