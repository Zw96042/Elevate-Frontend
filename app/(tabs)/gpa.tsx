import { useSettingSheet } from '@/context/SettingSheetContext';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from 'expo-router';
import React, { useCallback, useState } from 'react';
import { Alert, ScrollView, Text, TouchableOpacity, View } from 'react-native';

type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

interface GPAData {
  unweighted: number;
  weighted: number;
}

interface QuarterData {
  q1: GPAData;
  q2: GPAData;
  q3: GPAData;
  q4: GPAData;
  s1: GPAData;
  s2: GPAData;
  fullYear: GPAData;
}

const GPA = () => {
  const { settingSheetRef } = useSettingSheet();
  const [hasCredentials, setHasCredentials] = useState(false);
  const [selectedGrade, setSelectedGrade] = useState<GradeLevel>('Freshman');
  
  // Mock current grade level - replace with actual logic later
  const currentGradeLevel: GradeLevel = 'Junior';
  
  // Mock GPA data - replace with actual calculations later
  const mockGPAData: QuarterData = {
    q1: { unweighted: 3.85, weighted: 4.12 },
    q2: { unweighted: 3.92, weighted: 4.18 },
    q3: { unweighted: 3.78, weighted: 4.05 },
    q4: { unweighted: 3.95, weighted: 4.22 },
    s1: { unweighted: 3.89, weighted: 4.15 },
    s2: { unweighted: 3.87, weighted: 4.14 },
    fullYear: { unweighted: 3.88, weighted: 4.15 }
  };

  const gradeLevels: GradeLevel[] = ['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time'];
  
  // Filter grade levels based on current grade
  const availableGradeLevels = gradeLevels.filter((grade, index) => {
    const gradeIndex = gradeLevels.indexOf(currentGradeLevel);
    // Don't show "All Time" for freshmen
    if (grade === 'All Time' && gradeIndex === 0) {
      return false;
    }
    return index <= gradeIndex || grade === 'All Time';
  });

  useFocusEffect(
    useCallback(() => {
      const checkCredentials = async () => {
        const result = await SkywardAuth.hasCredentials();
        setHasCredentials(result);
      };

      checkCredentials();
    }, [])
  );

  const handlePDFUpload = () => {
    Alert.alert(
      'PDF Upload',
      'PDF upload functionality will be implemented later.',
      [{ text: 'OK' }]
    );
  };

  const renderPDFUploadSection = () => (
    <View className="flex-1 mt-8 px-6">
      <View className="bg-blue-900/30 rounded-2xl p-8 items-center justify-center w-full border border-blue-700/50">
        <View className="bg-blue-600/20 rounded-full p-4 mb-4">
          <Ionicons name="cloud-upload-outline" size={48} color="#60A5FA" />
        </View>
        <Text className="text-main text-xl font-semibold text-center mb-2">
          Upload Transcript
        </Text>
        <Text className="text-secondary text-center mb-6">
          Upload a PDF of your {selectedGrade} transcript to view your GPA
        </Text>
        <TouchableOpacity 
          onPress={handlePDFUpload}
          className="bg-blue-600 px-6 py-3 rounded-full"
        >
          <Text className="text-white font-medium">Choose PDF</Text>
        </TouchableOpacity>
      </View>
    </View>
  );

  const renderGPADisplay = () => (
    <ScrollView className="flex-1" showsVerticalScrollIndicator={false}>
      <View className="px-6 py-4">
        {/* RC1 and RC2 on same row */}
        <View className="flex-row justify-between mb-3">
          <View className="bg-cardColor rounded-lg px-3 py-2 w-[48%]">
            <Text className="text-main font-semibold text-sm mb-1">RC1</Text>
            <View className="flex-row justify-between">
              <View className="items-start">
                <Text className="text-secondary text-xs">Unweighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.q1.unweighted}</Text>
              </View>
              <View className="items-end">
                <Text className="text-secondary text-xs">Weighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.q1.weighted}</Text>
              </View>
            </View>
          </View>
          <View className="bg-cardColor rounded-lg px-3 py-2 w-[48%]">
            <Text className="text-main font-semibold text-sm mb-1">RC2</Text>
            <View className="flex-row justify-between">
              <View className="items-start">
                <Text className="text-secondary text-xs">Unweighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.q2.unweighted}</Text>
              </View>
              <View className="items-end">
                <Text className="text-secondary text-xs">Weighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.q2.weighted}</Text>
              </View>
            </View>
          </View>
        </View>

        {/* RC3 and RC4 on same row */}
        <View className="flex-row justify-between mb-3">
          <View className="bg-cardColor rounded-lg px-3 py-2 w-[48%]">
            <Text className="text-main font-semibold text-sm mb-1">RC3</Text>
            <View className="flex-row justify-between">
              <View className="items-start">
                <Text className="text-secondary text-xs">Unweighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.q3.unweighted}</Text>
              </View>
              <View className="items-end">
                <Text className="text-secondary text-xs">Weighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.q3.weighted}</Text>
              </View>
            </View>
          </View>
          <View className="bg-cardColor rounded-lg px-3 py-2 w-[48%]">
            <Text className="text-main font-semibold text-sm mb-1">RC4</Text>
            <View className="flex-row justify-between">
              <View className="items-start">
                <Text className="text-secondary text-xs">Unweighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.q4.unweighted}</Text>
              </View>
              <View className="items-end">
                <Text className="text-secondary text-xs">Weighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.q4.weighted}</Text>
              </View>
            </View>
          </View>
        </View>

        {/* SM1 and SM2 on same row */}
        <View className="flex-row justify-between mb-3">
          <View className="bg-cardColor rounded-lg px-3 py-2 w-[48%]">
            <Text className="text-main font-semibold text-sm mb-1">SM1</Text>
            <View className="flex-row justify-between">
              <View className="items-start">
                <Text className="text-secondary text-xs">Unweighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.s1.unweighted}</Text>
              </View>
              <View className="items-end">
                <Text className="text-secondary text-xs">Weighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.s1.weighted}</Text>
              </View>
            </View>
          </View>
          <View className="bg-cardColor rounded-lg px-3 py-2 w-[48%]">
            <Text className="text-main font-semibold text-sm mb-1">SM2</Text>
            <View className="flex-row justify-between">
              <View className="items-start">
                <Text className="text-secondary text-xs">Unweighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.s2.unweighted}</Text>
              </View>
              <View className="items-end">
                <Text className="text-secondary text-xs">Weighted</Text>
                <Text className="text-main text-sm font-bold">{mockGPAData.s2.weighted}</Text>
              </View>
            </View>
          </View>
        </View>

        {/* FIN on its own row with different style */}
        <View className="bg-cardColor rounded-xl px-4 py-3 flex-row items-center justify-between">
          <Text className="text-main font-bold text-lg">FIN</Text>
          <View className="flex-row items-center space-x-6">
            <View className="items-end mr-4">
              <Text className="text-secondary text-xs">Unweighted</Text>
              <Text className="text-main text-lg font-bold">{mockGPAData.fullYear.unweighted}</Text>
            </View>
            <View className="items-end">
              <Text className="text-secondary text-xs">Weighted</Text>
              <Text className="text-main text-lg font-bold">{mockGPAData.fullYear.weighted}</Text>
            </View>
          </View>
        </View>
      </View>
    </ScrollView>
  );

  const isCurrentGrade = selectedGrade === currentGradeLevel;
  const isPastGrade = gradeLevels.indexOf(selectedGrade) < gradeLevels.indexOf(currentGradeLevel);

  return (
    <View className="flex-1 bg-primary">
      {/* Header */}
      <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
        <Text className="text-white text-3xl font-bold">GPA</Text>
        <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
          <Ionicons name='cog-outline' color={'#fff'} size={26} />
        </TouchableOpacity>
      </View>

      {/* Grade Level Selectors - Moved out of header */}
      <View className="mt-4 pb-4 px-4">
        <View className="flex-row">
          {availableGradeLevels.map((grade, index) => (
            <TouchableOpacity
              key={grade}
              onPress={() => setSelectedGrade(grade)}
              className={`flex-1 mx-1 py-2 rounded-full ${
                selectedGrade === grade
                  ? 'bg-highlight border-highlight'
                  : 'border border-accent'
              }`}
            >
              <Text className={`font-medium text-center ${
                selectedGrade === grade ? 'text-highlightText font-bold' : 'text-main'
              } ${availableGradeLevels.length === 5 ? 'text-xs' : availableGradeLevels.length >= 4 ? 'text-xs' : 'text-sm'}`}>
                {grade}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      {/* Content Area */}
      <View className="flex-1 bg-primary">
        {isPastGrade ? renderPDFUploadSection() : renderGPADisplay()}
      </View>
    </View>
  );
};

export default GPA;