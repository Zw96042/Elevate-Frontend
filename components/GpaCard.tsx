import React from 'react';
import { Text, View } from 'react-native';

interface GPAData {
  unweighted: number;
  weighted: number;
}

interface GpaCardProps {
  label: string;
  data: GPAData;
}

export const GpaCard = ({ label, data }: GpaCardProps) => (
  <View className="bg-cardColor rounded-xl px-3 py-2 w-[48%]">
    <Text className="text-main font-semibold text-sm mb-1">{label}</Text>
    <View className="flex-row justify-between">
      <View className="items-start">
        <Text className="text-secondary text-xs">Unweighted</Text>
        <Text className="text-main text-sm font-bold">{data.unweighted === 0 ? '--' : data.unweighted.toFixed(2)}</Text>
      </View>
      <View className="items-end">
        <Text className="text-secondary text-xs">Weighted</Text>
        <Text className="text-main text-sm font-bold">{data.weighted === 0 ? '--' : data.weighted.toFixed(2)}</Text>
      </View>
    </View>
  </View>
);

export const GpaSoloCard = ({ label, data }: GpaCardProps) => (
  <View className="bg-cardColor rounded-xl px-4 py-3 flex-row items-center justify-between mb-5">
    <Text className="text-main font-bold text-lg">{label}</Text>
    <View className="flex-row items-center space-x-6">
      <View className="items-center">
        <Text className="text-secondary text-xs mr-3">Unweighted</Text>
        <Text className="text-main text-lg font-bold">{data.unweighted === 0 ? '--' : data.unweighted.toFixed(2)}</Text>
      </View>
      <View className="items-center">
        <Text className="text-secondary text-xs">Weighted</Text>
        <Text className="text-main text-lg font-bold">{data.weighted === 0 ? '--' : data.weighted.toFixed(2)}</Text>
      </View>
    </View>
  </View>
);