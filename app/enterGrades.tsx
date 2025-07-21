import React from 'react';
import { View, Text, TouchableOpacity } from 'react-native';

const EnterGrades = () => {
  return (
    <View className="flex-1 bg-primary items-center justify-center px-6">
      <TouchableOpacity className="bg-blue-600 px-6 py-3 rounded-full">
        <Text className="text-white font-medium text-lg">Add a class</Text>
      </TouchableOpacity>
    </View>
  );
};

export default EnterGrades;