import React from 'react';
import { View } from 'react-native';
import { MotiView } from 'moti';

const SkeletonGradeLevelSelector = () => {
  return (
    <View className="bg-cardColor rounded-xl px-4 py-3 flex-row items-center justify-between">
      <MotiView
        from={{ opacity: 0.5 }}
        animate={{ opacity: 1 }}
        transition={{
          type: 'timing',
          duration: 1000,
          loop: true,
        }}
        className="h-5 bg-gray-300 rounded w-24"
      />
      <MotiView
        from={{ opacity: 0.5 }}
        animate={{ opacity: 1 }}
        transition={{
          type: 'timing',
          duration: 1000,
          loop: true,
          delay: 200,
        }}
        className="w-4 h-4 bg-gray-300 rounded"
      />
    </View>
  );
};

export default SkeletonGradeLevelSelector;
