// components/MessageSkeleton.tsx
import React, { useEffect, useRef } from 'react';
import { Animated, View, useColorScheme } from 'react-native';
import MaskedView from '@react-native-masked-view/masked-view';
import LinearGradient from 'react-native-linear-gradient';

const SkeletonPlaceholder = ({ children }: { children: React.ReactNode }) => {
  const animatedValue = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.loop(
      Animated.timing(animatedValue, {
        toValue: 1,
        duration: 1200,
        useNativeDriver: true,
      })
    ).start();
  }, [animatedValue]);

  const translateX = animatedValue.interpolate({
    inputRange: [0, 1],
    outputRange: [-300, 300],
  });

  return (
    <MaskedView
      maskElement={
        <View className="bg-cardColor">{children}</View>
      }
    >
      <Animated.View style={{ transform: [{ translateX }] }}>
        <LinearGradient
          colors={['transparent', 'rgba(255,255,255,0.2)', 'transparent']}
          start={{ x: 0, y: 0.5 }}
          end={{ x: 1, y: 0.5 }}
          style={{ width: 300, height: '100%' }}
        />
      </Animated.View>
    </MaskedView>
  );
};

const SkeletonMessage = () => {
  return (
    <View className="w-full h-20 rounded-2xl bg-cardColor overflow-hidden">
      <SkeletonPlaceholder>
        <View className="w-full h-20 rounded-2xl bg-cardColor" />
      </SkeletonPlaceholder>
    </View>
  );
};

export default SkeletonMessage;