import React, { useEffect, useRef } from 'react';
import { Animated, View, StyleSheet } from 'react-native';
import MaskedView from '@react-native-masked-view/masked-view';
import LinearGradient from 'react-native-linear-gradient';

const SkeletonPlaceholder = ({ children }: { children: React.ReactNode }) => {
  const animatedValue1 = useRef(new Animated.Value(0)).current;
  const animatedValue2 = useRef(new Animated.Value(0)).current;
  const DURATION = 2000;

  useEffect(() => {
    animatedValue1.setValue(0);
    animatedValue2.setValue(0);

    const shimmer1 = Animated.loop(
      Animated.timing(animatedValue1, {
        toValue: 1,
        duration: DURATION,
        useNativeDriver: true,
      }),
      { iterations: -1 }
    );

    const shimmer2 = Animated.loop(
      Animated.timing(animatedValue2, {
        toValue: 1,
        duration: DURATION,
        useNativeDriver: true,
      }),
      { iterations: -1 }
    );

    shimmer1.start();
    const timeout = setTimeout(() => shimmer2.start(), DURATION / 3);

    return () => {
      clearTimeout(timeout);
      animatedValue1.stopAnimation();
      animatedValue2.stopAnimation();
    };
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
    <MaskedView
      style={{ flex: 1 }}
      maskElement={<View style={{ flex: 1 }}>{children}</View>}
    >
      <View style={{ flex: 1 }}>
        <Animated.View
          pointerEvents="none"
          style={{
            ...StyleSheet.absoluteFillObject,
            transform: [{ translateX: translateX1 }],
          }}
        >
          <LinearGradient
            colors={['transparent', 'rgba(255,255,255,0.22)', 'transparent']}
            start={{ x: 0, y: 0.5 }}
            end={{ x: 1, y: 0.5 }}
            style={{ width: 250, height: '100%' }}
          />
        </Animated.View>

        <Animated.View
          pointerEvents="none"
          style={{
            ...StyleSheet.absoluteFillObject,
            transform: [{ translateX: translateX2 }],
          }}
        >
          <LinearGradient
            colors={['transparent', 'rgba(255,255,255,0.22)', 'transparent']}
            start={{ x: 0, y: 0.5 }}
            end={{ x: 1, y: 0.5 }}
            style={{ width: 250, height: '100%' }}
          />
        </Animated.View>
      </View>
    </MaskedView>
  );
};

const SkeletonAssignment = () => {
  return (
    <View className="w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between px-5 animate-pulse">
      <SkeletonPlaceholder>
        <View className="w-full h-full flex-row items-center justify-between">
          <View className="flex-row">
            <View className="justify-center mt-1">
              <View className="w-24 h-5 bg-gray-300 rounded-md mb-2 ml-2" />
              <View className="w-48 h-6 bg-gray-300 rounded-md mb-1 ml-2" />
              <View className="w-16 h-4 bg-gray-200 rounded-md ml-2" />
            </View>
          </View>

          <View className="flex-row items-center mr-6">
            <View className="justify-center">
              <View className="w-10 h-10 rounded-full bg-gray-300" />
            </View>
            <View className="justify-center ml-[6px]">
              <View className="w-[1px] h-10 rounded-full bg-gray-300" />
            </View>
            <View className="justify-center ml-[6px]">
              <View className="w-10 h-10 rounded-full bg-gray-300" />
            </View>
          </View>
        </View>
      </SkeletonPlaceholder>
    </View>
  );
};

export default SkeletonAssignment;