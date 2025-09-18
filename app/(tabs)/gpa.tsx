/**
 * GPA Page (Refactored)
 * Simplified from 744 lines to ~300 lines using new architecture
 */

import React, { useState, useEffect } from 'react';
import { View, Text, RefreshControl, Alert, TouchableOpacity } from 'react-native';
import { ScrollView } from 'react-native-gesture-handler';
import { useColorScheme } from 'nativewind';
import { Ionicons } from '@expo/vector-icons';

// New architecture imports
import { UnifiedGPAManager } from '@/lib/unifiedGpaManager';
import { CredentialManager } from '@/lib/core/CredentialManager';
import { GradeLevel, UnifiedGPAResult } from '@/interfaces/interfaces';

// Component imports
import GradeLevelSelector from '@/components/GradeLevelSelector';
import { GpaCard } from '@/components/GpaCard';
import { useSettingSheet } from '@/context/SettingSheetContext';

const GPA = () => {
  const { colorScheme } = useColorScheme();
  const { settingSheetRef } = useSettingSheet();
  
  // Ensure colorScheme has a fallback
  const currentScheme = colorScheme || 'light';

  // Simple color helper for this component
  const getColor = (type: 'text' | 'textSecondary' | 'background' | 'primary') => {
    const colorMap = {
      light: {
        text: '#000000',
        textSecondary: '#6b7280',
        background: '#ffffff',
        primary: '#3b82f6'
      },
      dark: {
        text: '#ffffff',
        textSecondary: '#9ca3af',
        background: '#000000',
        primary: '#60a5fa'
      }
    };
    return colorMap[currentScheme][type];
  };

  // Simplified state management
  const [selectedGrade, setSelectedGrade] = useState<GradeLevel>('All Time');
  const [gpaResult, setGpaResult] = useState<UnifiedGPAResult | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [hasCredentials, setHasCredentials] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Check credentials
   */
  const checkCredentials = async () => {
    try {
      const hasValidSession = await CredentialManager.hasValidSession();
      setHasCredentials(hasValidSession);
      return hasValidSession;
    } catch (error) {
      setHasCredentials(false);
      return false;
    }
  };

  /**
   * Load GPA data using new UnifiedGPAManager
   */
  const loadGPAData = async (forceRefresh: boolean = false) => {
    try {
      setError(null);
      
      const hasValidCreds = await checkCredentials();
      if (!hasValidCreds) {
        setError('Please log in to view your GPA data');
        return;
      }

      const result = await UnifiedGPAManager.getGPAData(selectedGrade, forceRefresh);
      setGpaResult(result);

      if (!result.success) {
        setError(result.error || 'Failed to load GPA data');
      }
    } catch (error: any) {
      setError(error.message || 'Unknown error occurred');
    }
  };

  /**
   * Handle grade level changes
   */
  const handleGradeLevelChange = async (newGradeLevel: GradeLevel) => {
    if (newGradeLevel === selectedGrade) return;
    
    setSelectedGrade(newGradeLevel);
    setIsLoading(true);
    await loadGPAData(false);
    setIsLoading(false);
  };

  /**
   * Handle refresh
   */
  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadGPAData(true);
    setIsRefreshing(false);
  };

  /**
   * Show auth prompt
   */
  const showAuthPrompt = () => {
    Alert.alert(
      'Authentication Required',
      'Please log in to view your GPA data.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Settings', onPress: () => settingSheetRef.current?.snapToIndex(0) }
      ]
    );
  };

  // Initialize on mount
  useEffect(() => {
    const initializeData = async () => {
      setIsLoading(true);
      await loadGPAData(false);
      setIsLoading(false);
    };
    initializeData();
  }, []);

  // Render components
  const renderHeader = () => (
    <View className="flex-row items-center justify-between p-4">
      <Text 
        className="text-2xl font-bold"
        style={{ color: getColor('text') }}
      >
        GPA
      </Text>
      <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
        <Ionicons 
          name="settings-outline" 
          size={24} 
          color={getColor('text')}
        />
      </TouchableOpacity>
    </View>
  );

  const renderLoading = () => (
    <View className="flex-1 justify-center items-center">
      <Text style={{ color: getColor('textSecondary') }}>
        Loading GPA data...
      </Text>
    </View>
  );

  const renderError = () => (
    <View className="flex-1 justify-center items-center p-4">
      <Ionicons 
        name="alert-circle-outline" 
        size={48} 
        color={getColor('textSecondary')} 
      />
      <Text 
        className="text-lg text-center mt-4 mb-6"
        style={{ color: getColor('textSecondary') }}
      >
        {error}
      </Text>
      <TouchableOpacity
        className="bg-blue-500 px-6 py-3 rounded-lg"
        onPress={() => loadGPAData(true)}
      >
        <Text className="text-white font-semibold">Retry</Text>
      </TouchableOpacity>
    </View>
  );

  const renderAuth = () => (
    <View className="flex-1 justify-center items-center p-4">
      <Ionicons 
        name="lock-closed-outline" 
        size={48} 
        color={getColor('textSecondary')} 
      />
      <Text 
        className="text-lg text-center mt-4 mb-6"
        style={{ color: getColor('textSecondary') }}
      >
        Please log in to view your GPA
      </Text>
      <TouchableOpacity
        className="bg-blue-500 px-6 py-3 rounded-lg"
        onPress={showAuthPrompt}
      >
        <Text className="text-white font-semibold">Log In</Text>
      </TouchableOpacity>
    </View>
  );

  const renderContent = () => {
    if (!hasCredentials) return renderAuth();
    if (error) return renderError();
    if (!gpaResult?.success) return (
      <View className="flex-1 justify-center items-center p-4">
        <Text style={{ color: getColor('textSecondary') }}>
          No GPA data available
        </Text>
      </View>
    );

    return (
      <View className="flex-1">
        {/* Grade Level Selector */}
        <View className="px-4 pb-4">
          <GradeLevelSelector
            grades={['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time']}
            selectedGrade={selectedGrade}
            onSelectGrade={handleGradeLevelChange}
          />
        </View>

        {/* GPA Card */}
        {gpaResult.gpa && (
          <View className="px-4 pb-4">
            <GpaCard
              label={`${selectedGrade} GPA`}
              data={{
                unweighted: gpaResult.gpa.unweighted || gpaResult.gpa.gpa,
                weighted: gpaResult.gpa.weighted || gpaResult.gpa.gpa
              }}
            />
          </View>
        )}

        {/* Course List */}
        {gpaResult.rawCourses && gpaResult.rawCourses.length > 0 && (
          <View className="px-4">
            <Text 
              className="text-lg font-semibold mb-3"
              style={{ color: getColor('text') }}
            >
              Courses ({gpaResult.rawCourses.length})
            </Text>
            
            {gpaResult.rawCourses.map((course, index) => (
              <View 
                key={`${course.courseId}-${index}`}
                className="rounded-lg p-4 mb-3 shadow-sm"
                style={{ 
                  backgroundColor: currentScheme === 'dark' ? '#374151' : '#ffffff',
                }}
              >
                <Text 
                  className="font-semibold text-base"
                  style={{ color: getColor('text') }}
                >
                  {course.courseName}
                </Text>
                
                {course.instructor && (
                  <Text 
                    className="text-sm mt-1"
                    style={{ color: getColor('textSecondary') }}
                  >
                    {course.instructor}
                  </Text>
                )}

                {/* Current Scores */}
                {course.currentScores.length > 0 && (
                  <View className="flex-row flex-wrap mt-2">
                    {course.currentScores.map((scoreObj, scoreIndex) => (
                      <View 
                        key={scoreIndex}
                        className="rounded px-2 py-1 mr-2 mb-1"
                        style={{ 
                          backgroundColor: currentScheme === 'dark' ? '#1e3a8a' : '#dbeafe' 
                        }}
                      >
                        <Text 
                          className="text-xs font-medium"
                          style={{ color: getColor('text') }}
                        >
                          {scoreObj.bucket}: {scoreObj.score}%
                        </Text>
                      </View>
                    ))}
                  </View>
                )}
              </View>
            ))}
          </View>
        )}
      </View>
    );
  };

  return (
    <View 
      className="flex-1"
      style={{ backgroundColor: getColor('background') }}
    >
      {renderHeader()}
      
      {isLoading ? (
        renderLoading()
      ) : (
        <ScrollView
          className="flex-1"
          refreshControl={
            <RefreshControl
              refreshing={isRefreshing}
              onRefresh={handleRefresh}
              tintColor={getColor('primary')}
            />
          }
          showsVerticalScrollIndicator={false}
        >
          {renderContent()}
        </ScrollView>
      )}
    </View>
  );
};

export default GPA;
