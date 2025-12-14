import React, { useEffect, useRef, useMemo } from 'react';
import { Animated, View, StyleSheet } from 'react-native';
import MaskedView from '@react-native-masked-view/masked-view';
import { LinearGradient } from 'react-native-linear-gradient';
import { useScreenDimensions } from '@/hooks/useScreenDimensions';

const SkeletonPlaceholder = ({ children }: { children: React.ReactNode }) => {
  const animatedValue1 = useRef(new Animated.Value(0)).current;
  const animatedValue2 = useRef(new Animated.Value(0)).current;
  const DURATION = 2000;

  useEffect(() => {
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

const SkeletonClassCard = () => {
  const { height: screenHeight } = useScreenDimensions();
  
  // Calculate responsive height to match ClassCard (approximately 11% of screen height)
  const cardHeight = useMemo(() => {
    const responsiveHeight = Math.round(screenHeight * 0.0855);
    return Math.max(72, Math.min(120, responsiveHeight));
  }, [screenHeight]);

  return (
    <View 
      className="w-full rounded-3xl bg-cardColor flex-row items-center justify-between px-5 animate-pulse"
      style={{ height: cardHeight }}
    >
      <SkeletonPlaceholder>
        <View className='flex-1 justify-center'>
          <View className="w-40 h-6 bg-gray-300 rounded-md mb-2" />
          <View className="w-28 h-4 bg-gray-200 rounded-md" />
        </View>
      </SkeletonPlaceholder>

      <View className="flex-row items-center gap-4 mr-[5.25rem]">
        <SkeletonPlaceholder>
          <View className='flex-1 justify-center'>
            <View className="w-[50] h-[50] rounded-full bg-gray-300" />
          </View>
        </SkeletonPlaceholder>
      </View>
    </View>
  );
};

export default SkeletonClassCard;