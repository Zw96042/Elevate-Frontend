import React, { memo } from 'react';
import { Host, Picker } from '@expo/ui/swift-ui';
import { View } from 'moti';

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
  
  // Find the index of the currently selected grade
  const selectedIndex = grades.indexOf(selectedGrade);
  
  return (
    <View className='bg-cardColor'>
      <Host matchContents>
        <Picker
          options={grades}
          selectedIndex={selectedIndex >= 0 ? selectedIndex : 0}
          onOptionSelected={({ nativeEvent: { index } }) => {
            const newGrade = grades[index];
            console.log('👆 Grade picker selection changed:', newGrade);
            onSelectGrade(newGrade);
          }}
          variant="segmented"
        />
      </Host>
    </View>
  );
});

GradeLevelSelector.displayName = 'GradeLevelSelector';

export default GradeLevelSelector;