import React from 'react';
import { Text, TouchableOpacity, View } from 'react-native';

type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

interface Props {
  grades: GradeLevel[];
  selectedGrade: GradeLevel;
  onSelectGrade: (grade: GradeLevel) => void;
}

const GradeLevelSelector = ({ grades, selectedGrade, onSelectGrade }: Props) => {
  return (
    <View className="flex-row">
      {grades.map((grade) => (
        <TouchableOpacity
          key={grade}
          onPress={() => onSelectGrade(grade)}
          className={`flex-1 mx-1 py-2 rounded-full ${
            selectedGrade === grade
              ? 'bg-highlight border-highlight'
              : 'border border-accent'
          }`}
        >
          <Text className={`font-medium text-center ${
            selectedGrade === grade ? 'text-highlightText font-bold' : 'text-main'
          } ${grades.length > 4 ? 'text-xs leading-[20px]' : 'text-sm'}`}>
            {grade}
          </Text>
        </TouchableOpacity>
      ))}
    </View>
  );
};

export default GradeLevelSelector;