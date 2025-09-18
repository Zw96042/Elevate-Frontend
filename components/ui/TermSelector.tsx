/**
 * Term Selector Component
 * Handles term selection with visual feedback
 */

import React from 'react';
import { View, Text, TouchableOpacity, ScrollView, useColorScheme } from 'react-native';
import { TermLabel } from '@/interfaces/interfaces';

interface TermSelectorProps {
  selectedTerm: TermLabel;
  onTermSelect: (term: TermLabel) => void;
  availableTerms?: TermLabel[];
}

const DEFAULT_TERMS: TermLabel[] = [
  "Q1 Grades",
  "Q2 Grades", 
  "SM1 Grade",
  "Q3 Grades",
  "Q4 Grades",
  "SM2 Grades"
];

export const TermSelector: React.FC<TermSelectorProps> = ({
  selectedTerm,
  onTermSelect,
  availableTerms = DEFAULT_TERMS,
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const getTermDisplayName = (term: TermLabel): string => {
    switch (term) {
      case "Q1 Grades":
        return "Q1";
      case "Q2 Grades":
        return "Q2";
      case "SM1 Grade":
        return "S1";
      case "Q3 Grades":
        return "Q3";
      case "Q4 Grades":
        return "Q4";
      case "SM2 Grades":
        return "S2";
      default:
        return term;
    }
  };

  const getTermColor = (term: TermLabel): string => {
    // Different colors for different terms
    switch (term) {
      case "Q1 Grades":
      case "Q2 Grades":
        return '#3b82f6'; // Blue
      case "SM1 Grade":
        return '#8b5cf6'; // Purple
      case "Q3 Grades":
      case "Q4 Grades":
        return '#10b981'; // Green
      case "SM2 Grades":
        return '#f59e0b'; // Amber
      default:
        return '#6b7280'; // Gray
    }
  };

  const renderTermButton = (term: TermLabel) => {
    const isSelected = selectedTerm === term;
    const termColor = getTermColor(term);
    
    return (
      <TouchableOpacity
        key={term}
        onPress={() => onTermSelect(term)}
        style={{
          paddingHorizontal: 16,
          paddingVertical: 8,
          marginRight: 8,
          borderRadius: 20,
          backgroundColor: isSelected 
            ? termColor 
            : (isDark ? '#374151' : '#f3f4f6'),
          borderWidth: isSelected ? 0 : 1,
          borderColor: isDark ? '#4b5563' : '#d1d5db',
          minWidth: 50,
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <Text
          style={{
            color: isSelected 
              ? '#ffffff' 
              : (isDark ? '#d1d5db' : '#374151'),
            fontWeight: isSelected ? '600' : '500',
            fontSize: 14,
          }}
        >
          {getTermDisplayName(term)}
        </Text>
      </TouchableOpacity>
    );
  };

  return (
    <View style={{
      backgroundColor: isDark ? '#1f2937' : '#ffffff',
      paddingVertical: 12,
      borderBottomWidth: 1,
      borderBottomColor: isDark ? '#374151' : '#e5e7eb',
    }}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{
          paddingHorizontal: 16,
          alignItems: 'center',
        }}
      >
        {availableTerms.map(renderTermButton)}
      </ScrollView>
    </View>
  );
};
