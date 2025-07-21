import React from 'react';
import { Text, TouchableOpacity, View } from 'react-native';
import { useRouter } from 'expo-router';

const ManualGradeEntryCard = ({ selectedGrade }: { selectedGrade: string }) => {
  const router = useRouter();

  return (
    <View className="flex-1 mt-8 px-6">
      <View className="bg-cardColor rounded-2xl p-6 border border-dashed border-highlightText shadow-md flex items-center justify-center space-y-4">
        <Text className="text-main text-lg mb-3 text-center">
          Enter your {selectedGrade} year grades.
        </Text>
        <TouchableOpacity
          onPress={() => router.push('/enterGrades')}
          activeOpacity={0.8}
          className="bg-highlight px-6 py-2 rounded-full shadow-lg"
        >
          <Text className="text-highlightText font-semibold text-base text-center">
            Enter Grades
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

export default ManualGradeEntryCard;