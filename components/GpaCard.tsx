import React, { useMemo } from 'react';
import { Text, View } from 'react-native';
import { useScreenDimensions } from '@/hooks/useScreenDimensions';

interface GPAData {
  unweighted: number;
  weighted: number;
}

interface GpaCardProps {
  label: string;
  data: GPAData;
}

export const GpaCard = ({ label, data }: GpaCardProps) => {
  const { height: screenHeight } = useScreenDimensions();
  
  const cardStyles = useMemo(() => {
    if (screenHeight <= 852) {
      // 6.1", iPhone 13...
      return { height: 70, labelSize: 'text-xs', valueSize: 'text-xs', subLabelSize: 'text-[10px]', px: 'px-3', py: 'py-3' };
    } else if (screenHeight <= 912) {
      // 6.5", iPhone Air
      return { height: 82, labelSize: 'text-sm', valueSize: 'text-sm', subLabelSize: 'text-xs', px: 'px-4', py: 'py-4' };
    } else if (screenHeight <= 926) {
      // 6.7", iPhone 14 Plus...
      return { height: 85, labelSize: 'text-sm', valueSize: 'text-sm', subLabelSize: 'text-xs', px: 'px-4', py: 'py-4' };
    } else {
      // 6.9"+, iPhone 17 Pro Max...
      return { height: 90, labelSize: 'text-base', valueSize: 'text-base', subLabelSize: 'text-xs', px: 'px-4', py: 'py-4' };
    }
  }, [screenHeight]);

  return (
    <View 
      className={`bg-cardColor rounded-xl ${cardStyles.px} ${cardStyles.py} w-[48%]`}
      style={{ height: cardStyles.height }}
    >
      <Text className={`text-main font-semibold ${cardStyles.labelSize} mb-1`}>{label}</Text>
      <View className="flex-row justify-between">
        <View className="items-start">
          <Text className={`text-secondary ${cardStyles.subLabelSize}`}>Unweighted</Text>
          <Text className={`text-main ${cardStyles.valueSize} font-bold`}>{data.unweighted === 0 ? '--' : data.unweighted.toFixed(2)}</Text>
        </View>
        <View className="items-end">
          <Text className={`text-secondary ${cardStyles.subLabelSize}`}>Weighted</Text>
          <Text className={`text-main ${cardStyles.valueSize} font-bold`}>{data.weighted === 0 ? '--' : data.weighted.toFixed(2)}</Text>
        </View>
      </View>
    </View>
  );
};

export const GpaSoloCard = ({ label, data }: GpaCardProps) => {
  const { height: screenHeight } = useScreenDimensions();
  
  const cardStyles = useMemo(() => {
    if (screenHeight <= 852) {
      // 6.1" screens
      return { height: 55, labelSize: 'text-base', valueSize: 'text-base', subLabelSize: 'text-[10px]', px: 'px-3', py: 'py-2', mb: 'mb-3' };
    } else if (screenHeight <= 912) {
      // 6.5", iPhone Air
      return { height: 65, labelSize: 'text-lg', valueSize: 'text-lg', subLabelSize: 'text-xs', px: 'px-4', py: 'py-3', mb: 'mb-4' };
    } else if (screenHeight <= 926) {
      // 6.7", iPhone 14 Plus...
      return { height: 67, labelSize: 'text-lg', valueSize: 'text-lg', subLabelSize: 'text-xs', px: 'px-4', py: 'py-3', mb: 'mb-4' };
    } else {
      // 6.9"+ screens
      return { height: 68, labelSize: 'text-xl', valueSize: 'text-xl', subLabelSize: 'text-xs', px: 'px-4', py: 'py-3', mb: 'mb-5' };
    }
  }, [screenHeight]);

  return (
    <View 
      className={`bg-cardColor rounded-xl ${cardStyles.px} ${cardStyles.py} flex-row items-center justify-between ${cardStyles.mb}`}
      style={{ height: cardStyles.height }}
    >
      <Text className={`text-main font-bold ${cardStyles.labelSize}`}>{label}</Text>
      <View className="flex-row items-center space-x-6">
        <View className="items-center">
          <Text className={`text-secondary ${cardStyles.subLabelSize} mr-3`}>Unweighted</Text>
          <Text className={`text-main ${cardStyles.valueSize} font-bold`}>{data.unweighted === 0 ? '--' : data.unweighted.toFixed(2)}</Text>
        </View>
        <View className="items-center">
          <Text className={`text-secondary ${cardStyles.subLabelSize}`}>Weighted</Text>
          <Text className={`text-main ${cardStyles.valueSize} font-bold`}>{data.weighted === 0 ? '--' : data.weighted.toFixed(2)}</Text>
        </View>
      </View>
    </View>
  );
};