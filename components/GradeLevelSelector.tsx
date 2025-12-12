import React, { memo } from 'react';
import { Text, TouchableOpacity, View } from 'react-native';

type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

interface Props {
  grades: GradeLevel[];
  selectedGrade: GradeLevel;
  onSelectGrade: (grade: GradeLevel) => void;
}

const GradeLevelSelector = memo(({ grades, selectedGrade, onSelectGrade }: Props) => {
  console.log('🎨 GradeLevelSelector rendering with:', {
    grades,
    selectedGrade,
    gradesLength: grades.length
  });
  
  return (
    <View className="flex-row">
      {grades.map((grade) => {
        const isSelected = selectedGrade === grade;
        console.log(`🔘 Grade button "${grade}": isSelected=${isSelected} (selectedGrade="${selectedGrade}")`);
        return (
          <TouchableOpacity
            key={grade}
            onPress={() => {
              console.log('👆 Grade button pressed:', grade);
              onSelectGrade(grade);
            }}
            className={`flex-1 mx-1 py-2 rounded-full ${
              isSelected
                ? 'bg-highlight border-highlight'
                : 'border border-accent'
            }`}
          >
            <Text className={`font-medium text-center ${
              isSelected ? 'text-highlightText font-bold' : 'text-main'
            } ${grades.length > 4 ? 'text-xs leading-[20px]' : 'text-sm'}`}>
              {grade}
            </Text>
          </TouchableOpacity>
        );
      })}
    </View>
  );
});

GradeLevelSelector.displayName = 'GradeLevelSelector';

export default GradeLevelSelector;