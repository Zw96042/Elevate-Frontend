import React, { useEffect, useRef } from 'react';
import { Animated, Text, TouchableOpacity, View } from 'react-native';
import MaskedView from '@react-native-masked-view/masked-view';
import LinearGradient from 'react-native-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import Skeleton from "react-native-reanimated-skeleton";

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
    <TouchableOpacity  className='w-[100%]'>
      <Skeleton isLoading={true}>
            <View className='w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between'>
                <View>
                    <View className="self-start rounded-md bg-highlight px-2 ml-5">
                      <Text className="text-sm text-highlightText font-bold">
                        AP Pre Calc
                      </Text>
                    </View>
                    <Text className='text-lg text-main font-medium ml-5'>
                      AP Pre Calc Exam Tomorrow Morning @
                    </Text>
                    <Text className='text-xs text-secondary ml-5'>
                      KENZIE SANCHEZ   MON MAY 12 2025 637pm
                    </Text>
                </View>
                <View className='flex-row items-center'>
                    <Ionicons name="chevron-forward" size={24} color="#cbd5e1" className='mr-3'/>
                </View>
                
            </View>
          </Skeleton>
        </TouchableOpacity>
  );
};

export default SkeletonMessage;