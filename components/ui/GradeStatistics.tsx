/**
 * Grade Statistics Component
 * Displays detailed grade breakdown and category information
 */

import React from 'react';
import { View, Text, useColorScheme } from 'react-native';
import { TermData } from '@/interfaces/interfaces';

interface GradeStatisticsProps {
  termData: TermData;
  courseSummary: {
    courseTotal: string;
    categories: Record<string, {
      average: number;
      weight: number;
      rawPoints: number;
      rawTotal: number;
    }>;
  };
  showDetails?: boolean;
}

export const GradeStatistics: React.FC<GradeStatisticsProps> = ({
  termData,
  courseSummary,
  showDetails = true,
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const getPercentageColor = (percentage: number): string => {
    if (percentage >= 90) return '#10b981'; // Green
    if (percentage >= 80) return '#f59e0b'; // Amber
    if (percentage >= 70) return '#f97316'; // Orange
    return '#ef4444'; // Red
  };

  const formatPercentage = (value: number): string => {
    return isNaN(value) ? '--' : `${Math.round(value)}%`;
  };

  const renderCategoryRow = (categoryName: string, index: number) => {
    const categoryData = courseSummary.categories[categoryName];
    const weight = termData.categories.weights[index] || 0;
    
    if (!categoryData) return null;

    return (
      <View
        key={categoryName}
        style={{
          flexDirection: 'row',
          justifyContent: 'space-between',
          alignItems: 'center',
          paddingVertical: 8,
          paddingHorizontal: 12,
          backgroundColor: isDark ? '#374151' : '#f9fafb',
          marginBottom: 4,
          borderRadius: 8,
        }}
      >
        <View style={{ flex: 1 }}>
          <Text
            style={{
              fontSize: 14,
              fontWeight: '500',
              color: isDark ? '#f3f4f6' : '#1f2937',
              marginBottom: 2,
            }}
          >
            {categoryName}
          </Text>
          <Text
            style={{
              fontSize: 12,
              color: isDark ? '#9ca3af' : '#6b7280',
            }}
          >
            Weight: {weight}%
          </Text>
        </View>
        
        <View style={{ alignItems: 'flex-end' }}>
          <Text
            style={{
              fontSize: 16,
              fontWeight: '600',
              color: getPercentageColor(categoryData.average),
              marginBottom: 2,
            }}
          >
            {formatPercentage(categoryData.average)}
          </Text>
          <Text
            style={{
              fontSize: 12,
              color: isDark ? '#9ca3af' : '#6b7280',
            }}
          >
            {categoryData.rawPoints.toFixed(1)}/{categoryData.rawTotal.toFixed(1)}
          </Text>
        </View>
      </View>
    );
  };

  const overallGrade = typeof termData.total === 'number' ? termData.total : 0;

  return (
    <View
      style={{
        backgroundColor: isDark ? '#1f2937' : '#ffffff',
        margin: 16,
        borderRadius: 12,
        padding: 16,
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.1,
        shadowRadius: 4,
        elevation: 3,
      }}
    >
      {/* Overall Grade */}
      <View
        style={{
          alignItems: 'center',
          marginBottom: showDetails ? 20 : 0,
        }}
      >
        <Text
          style={{
            fontSize: 24,
            fontWeight: 'bold',
            color: getPercentageColor(overallGrade),
            marginBottom: 4,
          }}
        >
          {formatPercentage(overallGrade)}
        </Text>
        <Text
          style={{
            fontSize: 14,
            color: isDark ? '#9ca3af' : '#6b7280',
          }}
        >
          Overall Grade
        </Text>
      </View>

      {/* Category Breakdown */}
      {showDetails && termData.categories.names.length > 0 && (
        <View>
          <Text
            style={{
              fontSize: 16,
              fontWeight: '600',
              color: isDark ? '#f3f4f6' : '#1f2937',
              marginBottom: 12,
            }}
          >
            Category Breakdown
          </Text>
          
          {termData.categories.names.map((categoryName, index) =>
            renderCategoryRow(categoryName, index)
          )}
        </View>
      )}

      {/* Summary Stats */}
      {showDetails && Object.keys(courseSummary.categories).length > 0 && (
        <View
          style={{
            marginTop: 16,
            paddingTop: 16,
            borderTopWidth: 1,
            borderTopColor: isDark ? '#374151' : '#e5e7eb',
          }}
        >
          <View
            style={{
              flexDirection: 'row',
              justifyContent: 'space-between',
            }}
          >
            <Text
              style={{
                fontSize: 14,
                color: isDark ? '#9ca3af' : '#6b7280',
              }}
            >
              Categories: {termData.categories.names.length}
            </Text>
            <Text
              style={{
                fontSize: 14,
                color: isDark ? '#9ca3af' : '#6b7280',
              }}
            >
              Course Total: {courseSummary.courseTotal}
            </Text>
          </View>
        </View>
      )}
    </View>
  );
};
