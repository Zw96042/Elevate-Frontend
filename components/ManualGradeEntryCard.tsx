import React, { useEffect, useState } from 'react';
import { Text, TouchableOpacity, View } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useFocusEffect, useRouter } from 'expo-router';
import { useIsFocused } from '@react-navigation/native';

const ManualGradeEntryCard = ({ selectedGrade }: { selectedGrade: string }) => {
  const router = useRouter();
  const [savedClasses, setSavedClasses] = useState<any[]>([]); // You can replace any[] with your class type if defined

  useFocusEffect(() => {
    const loadSavedClasses = async () => {
      try {
        const stored = await AsyncStorage.getItem(`savedClasses-${selectedGrade}`);
        const parsed = stored ? JSON.parse(stored) : [];
        setSavedClasses(parsed);
      } catch (error) {
        console.error('Failed to load saved classes:', error);
      }
    };

      loadSavedClasses();
  });

  return (
    <View className="flex-1 mt-2 px-6">
      <View className="bg-cardColor rounded-2xl p-6 border border-dashed border-highlightText shadow-md flex items-center justify-center space-y-4">
        <Text className="text-main text-lg mb-3 text-center">
          Enter your {selectedGrade} year grades.
        </Text>
        <TouchableOpacity
          onPress={() => router.push({
            pathname: '/enterGrades/[gradeLevel]',
            params: {
              gradeLevel: selectedGrade,
              preloadedClasses: JSON.stringify(savedClasses),
            }
          })}
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