import { useSettingSheet } from '@/context/SettingSheetContext';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import React, { JSX, useCallback, useState } from 'react';
import { Alert, Dimensions, ScrollView, Text, TouchableOpacity, View } from 'react-native';
import Svg, { Defs, LinearGradient, Path, Stop } from 'react-native-svg';

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

const gpaScale = 100; // Change this to 4, 5, etc. as needed

const GPA = () => {
  const { settingSheetRef } = useSettingSheet();
  const [hasCredentials, setHasCredentials] = useState(false);
  const [selectedGrade, setSelectedGrade] = useState<GradeLevel>('Freshman');
  
  // Mock current grade level - replace with actual logic later
  const currentGradeLevel: GradeLevel = 'Sophomore';
  
  const allLabels = ['PR1','PR2','RC1','PR3','PR4','RC2','PR5','PR6','RC3','PR7','PR8','RC4'];

  const mockGPAData: Record<string, GPAData> = {
    PR1: { unweighted: 88, weighted: 105 },
    PR2: { unweighted: 91, weighted: 90 },
    RC1: { unweighted: 90, weighted: 95 },
    PR3: { unweighted: 85, weighted: 110 },
    PR4: { unweighted: 89, weighted: 50 },
    RC2: { unweighted: 92, weighted: 96 },
    PR5: { unweighted: 92, weighted: 91 },
    PR6: { unweighted: 86, weighted: 85 },
    SM1: { unweighted: 91, weighted: 97 },
    FIN: { unweighted: 94, weighted: 98 },
  };

  const validLabels = allLabels.filter(label => mockGPAData[label] && mockGPAData[label].weighted > 0);

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

  const renderGPAGraph = () => {
    const screenWidth = Dimensions.get('window').width;
    const graphWidth = screenWidth - 42; // Account for padding
    const graphHeight = 100;
    const containerWidth = screenWidth - 24; // Account for mx-6 (12px on each side) and px-4 (16px on each side)

    // GPA progression data points (weighted GPA values), dynamic for all 12 terms
    // const allLabels = ['PR1','PR2','RC1','PR3','PR4','RC2','PR5','PR6','RC3','PR7','PR8','RC4'];
    // const validLabels = allLabels.filter(label => mockGPAData[label].weighted > 0);
    const gpaPoints = validLabels.map(label => mockGPAData[label].weighted);

    // Normalize GPA values to graph coordinates with proper padding
    const numSegments = gpaPoints.length - 1;
    const normalizedPoints = gpaPoints.map((gpa, index) => {
      const x = (index / numSegments) * graphWidth;
      // y = top + (max - value) / (max - min) * height
      const y = 30 + ((gpaScale - gpa) / gpaScale) * (graphHeight - 20);
      return { x, y };
    });

    /*
    const normalizedPoints = gpaPoints.slice(0, gpaPoints.length - 1).map((gpa, index) => {
      const x = 20 + (index / (gpaPoints.length - 2)) * (graphWidth - 40);
      const y = 10 + graphHeight - ((gpa - 3.0) / 2.0) * (graphHeight - 20);
      return { x, y };
    });

    const normalizedPoints = gpaPoints.slice(0, numSegments).map((gpa, index) => {
      const x = (index / numSegments ) * graphWidth;
      const y = 10 + graphHeight - ((gpa - 3.0) / 2.0) * (graphHeight - 20);
      return { x, y };
    });
    */
    
    // Create smooth SVG path with curves
    const pathData = normalizedPoints.map((point, index) => {
      if (index === 0) return `M ${point.x} ${point.y}`;
      const prevPoint = normalizedPoints[index - 1];
      const controlX1 = prevPoint.x + (point.x - prevPoint.x) * 0.3;
      const controlY1 = prevPoint.y;
      const controlX2 = point.x - (point.x - prevPoint.x) * 0.3;
      const controlY2 = point.y;
      return `C ${controlX1} ${controlY1} ${controlX2} ${controlY2} ${point.x} ${point.y}`;
    }).join(' ');
    
    // Create fill path (area under the line)
    const fillPathData = pathData + ` L ${graphWidth} ${graphHeight - 10} L 0 ${graphHeight - 10} Z`;
    
    return (
      <View className="mb-6 bg-cardColor rounded-xl pt-4">
        <Text className="text-main text-lg text-center">Weighted GPA Graph</Text>
        <View className={`w-full h-[${graphHeight + 20}] relative overflow-hidden`}>
          <Svg
            width="100%"
            height={graphHeight}
            viewBox={`0 0 ${graphWidth } ${graphHeight}`}
          >
            <Defs>
              <LinearGradient id="gradient" x1="0%" y1="0%" x2="0%" y2="100%">
                <Stop offset="0%" stopColor="#138EED" stopOpacity="0.4" />
                <Stop offset="100%" stopColor="#058FFB" stopOpacity="0" />
              </LinearGradient>
            </Defs>
            <Path d={fillPathData} fill="url(#gradient)" />
            {/* Line */}
            <Path d={pathData} stroke="#0090FF" strokeWidth="2" fill="none" />
          </Svg>
          <MotiView
            from={{ width: containerWidth - 17 }}
            animate={{ width: 0}}
            transition={{
              type: 'spring', 
              damping: 1000, 
              mass: 10,
              stiffness: 80, 
              restDisplacementThreshold: 0.01,
              restSpeedThreshold: 0.001,
            }}
            style={{
              position: 'absolute',
              top: 0,
              bottom: 0,
              right: 0,
            }}
            className='bg-cardColor mb-2'
          />

          {/* <View className="flex-row justify-between px-2">
            {validLabels.map(label => (
                <Text
                  key={label}
                  className="text-secondary text-xs"
                >
                  {label}
                </Text>
            ))}
          </View> */}
        </View>
      </View>
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
      <View className="px-6 pb-4">
        {/* GPA Graph */}
        {renderGPAGraph()}

        {/* Dynamic GPA cards */}
        <View className="flex-1">
          {(() => {
            const fallback: GPAData = { unweighted: 100, weighted: 100 };
            const getData = (label: string) => mockGPAData[label] || fallback;

            const hasRC3or4 = !!mockGPAData["RC3"] || !!mockGPAData["RC4"];
            const hasSM2 = !!mockGPAData["SM2"] || true; // Always assume SM2 exists

            const rcPairs = [
              ["RC1", "RC2"],
              ["RC3", "RC4"],
            ];
            const prPairs = [
              ["PR1", "PR2"],
              ["PR3", "PR4"],
              ["PR5", "PR6"],
              ["PR7", "PR8"],
            ];

            // Find latest PR pair with both non-100
            let latestPRPair: string[] | null = null;
            for (let i = prPairs.length - 1; i >= 0; i--) {
              const [a, b] = prPairs[i];
              const aValid = mockGPAData[a] && mockGPAData[a].weighted !== 100;
              const bValid = mockGPAData[b] && mockGPAData[b].weighted !== 100;
              if (aValid && bValid) {
                latestPRPair = [a, b];
                break;
              }
            }

            const rows: JSX.Element[] = [];

            // RC1 + RC2
            rows.push(
              <View className="flex-row justify-between mb-3" key="rc1-rc2">
                {rcPairs[0].map(label => (
                  <View key={label} className="bg-cardColor rounded-xl px-3 py-2 w-[48%]">
                    <Text className="text-main font-semibold text-sm mb-1">{label}</Text>
                    <View className="flex-row justify-between">
                      <View className="items-start">
                        <Text className="text-secondary text-xs">Unweighted</Text>
                        <Text className="text-main text-sm font-bold">
                          {mockGPAData[label] ? mockGPAData[label].unweighted : "--"}
                        </Text>
                      </View>
                      <View className="items-end">
                        <Text className="text-secondary text-xs">Weighted</Text>
                        <Text className="text-main text-sm font-bold">
                          {mockGPAData[label] ? mockGPAData[label].weighted : "--"}
                        </Text>
                      </View>
                    </View>
                  </View>
                ))}
              </View>
            );

            // SM1 - standardized card
            rows.push(
              <View className="bg-cardColor rounded-xl px-4 py-3 flex-row items-center justify-between mb-5" key="SM1">
                <Text className="text-main font-bold text-lg">SM1</Text>
                <View className="flex-row items-center space-x-6">
                  <View className="items-center">
                    <Text className="text-secondary text-xs mr-3">Unweighted</Text>
                    <Text className="text-main text-lg font-bold">
                      {mockGPAData["SM1"] ? mockGPAData["SM1"].unweighted : "--"}
                    </Text>
                  </View>
                  <View className="items-center">
                    <Text className="text-secondary text-xs">Weighted</Text>
                    <Text className="text-main text-lg font-bold">
                      {mockGPAData["SM1"] ? mockGPAData["SM1"].weighted : "--"}
                    </Text>
                  </View>
                </View>
              </View>
            );

            // PR if no RC3/RC4
            if (!hasRC3or4 && latestPRPair) {
              rows.push(
                <View className="flex-row justify-between mb-3" key="latest-pr">
                  {latestPRPair.map(label => (
                    <View key={label} className="bg-cardColor rounded-xl px-3 py-2 w-[48%]">
                      <Text className="text-main font-semibold text-sm mb-1">{label}</Text>
                      <View className="flex-row justify-between">
                        <View className="items-start">
                          <Text className="text-secondary text-xs">Unweighted</Text>
                          <Text className="text-main text-sm font-bold">
                            {mockGPAData[label] ? mockGPAData[label].unweighted : "--"}
                          </Text>
                        </View>
                        <View className="items-end">
                          <Text className="text-secondary text-xs">Weighted</Text>
                          <Text className="text-main text-sm font-bold">
                            {mockGPAData[label] ? mockGPAData[label].weighted : "--"}
                          </Text>
                        </View>
                      </View>
                    </View>
                  ))}
                </View>
              );
            }

            // RC3 + RC4
            rows.push(
              <View className="flex-row justify-between mb-3" key="rc3-rc4">
                {rcPairs[1].map(label => (
                  <View key={label} className="bg-cardColor rounded-xl px-3 py-2 w-[48%]">
                    <Text className="text-main font-semibold text-sm mb-1">{label}</Text>
                    <View className="flex-row justify-between">
                      <View className="items-start">
                        <Text className="text-secondary text-xs">Unweighted</Text>
                        <Text className="text-main text-sm font-bold">
                          {mockGPAData[label] ? mockGPAData[label].unweighted : "--"}
                        </Text>
                      </View>
                      <View className="items-end">
                        <Text className="text-secondary text-xs">Weighted</Text>
                        <Text className="text-main text-sm font-bold">
                          {mockGPAData[label] ? mockGPAData[label].weighted : "--"}
                        </Text>
                      </View>
                    </View>
                  </View>
                ))}
              </View>
            );

            // SM2 - standardized card
            rows.push(
              <View className="bg-cardColor rounded-xl px-4 py-3 flex-row items-center justify-between mb-5" key="SM2">
                <Text className="text-main font-bold text-lg">SM2</Text>
                <View className="flex-row items-center space-x-6">
                  <View className="items-center">
                    <Text className="text-secondary text-xs mr-3">Unweighted</Text>
                    <Text className="text-main text-lg font-bold">
                      {mockGPAData["SM2"] ? mockGPAData["SM2"].unweighted : "--"}
                    </Text>
                  </View>
                  <View className="items-center">
                    <Text className="text-secondary text-xs">Weighted</Text>
                    <Text className="text-main text-lg font-bold">
                      {mockGPAData["SM2"] ? mockGPAData["SM2"].weighted : "--"}
                    </Text>
                  </View>
                </View>
              </View>
            );

            // FIN - standardized card
            if (hasSM2) {
              const sm1 = mockGPAData["SM1"] || fallback;
              const sm2 = mockGPAData["SM2"] || fallback;

              const finUnweighted = (sm1.unweighted + sm2.unweighted) / 2;
              const finWeighted = (sm1.weighted + sm2.weighted) / 2;

              rows.push(
                <View className="bg-cardColor rounded-xl px-4 py-3 flex-row items-center justify-between mb-5" key="FIN">
                  <Text className="text-main font-bold text-lg">FIN</Text>
                  <View className="flex-row items-center space-x-6">
                    <View className="items-center">
                      <Text className="text-secondary text-xs mr-3">Unweighted</Text>
                      <Text className="text-main text-lg font-bold">
                        {finUnweighted.toFixed(2)}
                      </Text>
                    </View>
                    <View className="items-center">
                      <Text className="text-secondary text-xs">Weighted</Text>
                      <Text className="text-main text-lg font-bold">
                        {finWeighted.toFixed(2)}
                      </Text>
                    </View>
                  </View>
                </View>
              );
            }

            return rows;
          })()}
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