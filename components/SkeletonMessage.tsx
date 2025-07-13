import React, { useEffect, useRef } from 'react';
import { Animated, Text, TouchableOpacity, View, Easing, StyleSheet } from 'react-native';
import MaskedView from '@react-native-masked-view/masked-view';
import LinearGradient from 'react-native-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import Skeleton from "react-native-reanimated-skeleton";

const SkeletonPlaceholder = ({ children }: { children: React.ReactNode }) => {
  const animatedValue1 = useRef(new Animated.Value(0)).current;
  const animatedValue2 = useRef(new Animated.Value(0)).current;
  const DURATION = 2000;

  useEffect(() => {
    const shimmer1 = Animated.loop(
      Animated.timing(animatedValue1, {
        toValue: 1,
        duration: DURATION,
        // easing: Easing.cubic,
        useNativeDriver: true,
      }),
      { iterations: -1 }
    );
    const shimmer2 = Animated.loop(
      Animated.timing(animatedValue2, {
        toValue: 1,
        duration: DURATION,
        // easing: Easing.cubic,
        useNativeDriver: true,
      }),
      { iterations: -1 }
    );

    shimmer1.start();

    const timeout = setTimeout(() => {
      shimmer2.start();
    }, DURATION / 3);

    return () => clearTimeout(timeout);
  }, [animatedValue1, animatedValue2]);

  const translateX1 = animatedValue1.interpolate({
    inputRange: [0, 1],
    outputRange: [-300, 300],
  });
  const translateX2 = animatedValue2.interpolate({
    inputRange: [0, 1],
    outputRange: [-300, 300],
  });

  return (
    <MaskedView maskElement={<View className="absolute inset-0">{children}</View>}>
      <View style={{ flex: 1 }}>
        <Animated.View
          style={{
            ...StyleSheet.absoluteFillObject,
            transform: [{ translateX: translateX1 }],
          }}
        >
          <LinearGradient
            colors={['transparent', 'rgba(255,255,255,0.2)', 'transparent']}
            start={{ x: 0, y: 0.5 }}
            end={{ x: 1, y: 0.5 }}
            style={{ width: 250, height: '100%' }}
          />
        </Animated.View>
        <Animated.View
          style={{
            ...StyleSheet.absoluteFillObject,
            transform: [{ translateX: translateX2 }],
          }}
        >
          <LinearGradient
            colors={['transparent', 'rgba(255,255,255,0.2)', 'transparent']}
            start={{ x: 0, y: 0.5 }}
            end={{ x: 1, y: 0.5 }}
            style={{ width: 250, height: '100%' }}
          />
        </Animated.View>
      </View>
    </MaskedView>
  );
};

const SkeletonMessage = () => {
  return (
    <View className="w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between px-5 animate-pulse">
      <SkeletonPlaceholder>
        <View className="flex-1 justify-center">
          <View className="w-20 h-5 bg-highlight rounded-md mb-2" />
          <View className="w-[18rem] h-5 bg-gray-300 rounded-md mb-1" />
          <View className="w-[10rem] h-3 bg-gray-200 rounded-md" />
        </View>
      </SkeletonPlaceholder>
      
    </View>
  );
};

export default SkeletonMessage;