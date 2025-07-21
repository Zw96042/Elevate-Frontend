import { useSettingSheet } from '@/context/SettingSheetContext';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from 'expo-router';
import { MotiView } from 'moti';
import React, { JSX, useCallback, useState } from 'react';
import { Alert, Dimensions, PanResponder, ScrollView, Text, TouchableOpacity, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Path, Stop } from 'react-native-svg';

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
  const [activePointIndex, setActivePointIndex] = useState<number | null>(null);
  
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
    SM1: { unweighted: 91, weighted: 97 },
    PR5: { unweighted: 92, weighted: 91 },
    PR6: { unweighted: 86, weighted: 85 },
    RC3: { unweighted: 90, weighted: 95 },
    PR7: { unweighted: 85, weighted: 110 },
    PR8: { unweighted: 89, weighted: 50 },
    RC4: { unweighted: 92, weighted: 96 },
    SM2: { unweighted: 91, weighted: 97 },
  };

  const validLabels = allLabels.filter(label => mockGPAData[label] && mockGPAData[label].weighted > 0);

  const gradeLevels: GradeLevel[] = ['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time'];
  
  const availableGradeLevels = gradeLevels.filter((grade, index) => {
    const gradeIndex = gradeLevels.indexOf(currentGradeLevel);
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
    const graphWidth = screenWidth - 42; 
    const graphHeight = 100;
    const containerWidth = screenWidth - 24; 

    const gpaPoints = validLabels.map(label => mockGPAData[label].weighted);

    // Prevent rendering with insufficient data
    if (gpaPoints.length < 2) {
      return (
        <View className="mb-4 bg-cardColor rounded-xl pt-8 overflow-hidden">
          <Text className="text-main text-lg text-center">Weighted GPA Graph</Text>
          <Text className="text-secondary text-center py-6">Not enough data to render graph.</Text>
        </View>
      );
    }

    const numSegments = gpaPoints.length - 1;
    const normalizedPoints = gpaPoints.map((gpa, index) => {
      const x = (index / numSegments) * graphWidth;
      const y = 30 + ((gpaScale - gpa) / gpaScale) * (graphHeight - 20);
      return { x, y };
    });
    const segmentWidth = graphWidth / (gpaPoints.length - 1);

    // PanResponder for touch gestures
    const panResponder = PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onPanResponderGrant: (evt) => {
        const x = evt.nativeEvent.locationX;
        const idx = Math.floor((x + segmentWidth / 2) / segmentWidth);
        setActivePointIndex(Math.max(0, Math.min(idx, gpaPoints.length - 1)));
      },
      onPanResponderMove: (evt) => {
        const x = evt.nativeEvent.locationX;
        const idx = Math.floor((x + segmentWidth / 2) / segmentWidth);
        setActivePointIndex(Math.max(0, Math.min(idx, gpaPoints.length - 1)));
      },
      onPanResponderRelease: () => {
        setActivePointIndex(null);
      }
    });

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
    const fillPathData = pathData + ` L ${graphWidth} ${graphHeight + 5} L 0 ${graphHeight} Z`;

    return (
      <View className="mb-4 bg-cardColor rounded-xl pt-4 overflow-hidden">
        <Text className="text-main text-lg text-center mb-4">Weighted GPA Graph</Text>
        <View className={`w-full relative`} {...panResponder.panHandlers}>
          <View style={{ height: graphHeight, overflow: 'hidden' }}>
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
              {/* Active point: blue dot */}
              {activePointIndex !== null && (
                <Circle
                  cx={normalizedPoints[activePointIndex].x}
                  cy={normalizedPoints[activePointIndex].y}
                  r={5}
                  fill="#0A84FF"
                  stroke="white"
                  strokeWidth={2}
                />
              )}
            </Svg>
          </View>
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
            className='bg-cardColor'
          />
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

  const renderGPADisplay = () => {
    const screenWidth = Dimensions.get('window').width;
    const graphWidth = screenWidth - 42; 
    const graphHeight = 100;
    const gpaPoints = validLabels.map(label => mockGPAData[label].weighted);
    
    const numSegments = gpaPoints.length - 1;
    const normalizedPoints = gpaPoints.map((gpa, index) => {
      const x = (index / numSegments) * graphWidth;
      const y = 30 + ((gpaScale - gpa) / gpaScale) * (graphHeight - 20);
      return { x, y };
    });

    return (
      <ScrollView className="flex-1" showsVerticalScrollIndicator={false} scrollEnabled={false}>
        <View className="px-6 pb-4">
          {/* GPA Graph */}
          {renderGPAGraph()}
          
          {/* Tooltip overlay at the highest level */}
          {activePointIndex !== null && gpaPoints.length >= 2 && (() => {
            const tooltipWidth = 140; // maxWidth
            const tooltipHeight = 40; // approximate height
            const padding = 24; // container padding
            
            // Use the actual device screen width
            const actualScreenWidth = Dimensions.get('window').width;
            const graphWidth = actualScreenWidth - 42; // Same as in renderGPAGraph
            const containerWidth = actualScreenWidth - 24; // Same as in renderGPAGraph
            
            // Calculate initial position relative to graph
            const graphLeft = padding; // Left edge of graph container
            const graphRight = graphLeft + graphWidth - 10; // Right edge minus small buffer for tooltip
            
            console.log("ACTUAL screen width:", actualScreenWidth);
            console.log("Graph width:", graphWidth);
            console.log("Graph right edge:", graphRight);
            
            // The normalizedPoints are already scaled to fit within graphWidth
            // So we just need to add the graph's left position
            const screenX = graphLeft + normalizedPoints[activePointIndex].x;
            let left = screenX - (tooltipWidth / 2); // Center tooltip on cursor
            let top = normalizedPoints[activePointIndex].y; // Reduced from 120 to be closer to cursor
            
            console.log("normalized x:", normalizedPoints[activePointIndex].x);
            console.log("screen x:", screenX);
            console.log("tooltip left:", left);
            console.log("tooltip right edge:", left + tooltipWidth);
            console.log("graph right edge:", graphRight);
            console.log("graph left edge:", graphLeft);

            // Check if tooltip would be cut off on the right (allow a larger buffer before restricting)
            console.log("Checking right edge:", left + tooltipWidth, ">", graphRight + 60, "=", left + tooltipWidth > graphRight + 55);
            if (left + tooltipWidth > graphRight + 55) {
              const overshoot = (left + tooltipWidth) - (graphRight + 55);
              left = left - overshoot - 10; // Adjust just enough to keep it within bounds
              console.log("ADJUSTED RIGHT - new left:", left);
            }
            
            // Check if tooltip would be cut off on the left
            if (left < graphLeft) {
              left = graphLeft;
              console.log("ADJUSTED LEFT - new left:", left);
            }
            
            console.log("FINAL left position:", left);
            
            // Check if tooltip would be cut off at the bottom (optional)
            const screenHeight = Dimensions.get('window').height;
            if (top + tooltipHeight > screenHeight - 100) {
              top = normalizedPoints[activePointIndex].y - tooltipHeight - 20; // Show above cursor
            }
            
            return (
              <View
                pointerEvents="none"
                style={{
                  position: 'absolute',
                  top,
                  left,
                  backgroundColor: 'rgba(30, 41, 59, 0.95)',
                  paddingVertical: 6,
                  paddingHorizontal: 12,
                  borderRadius: 10,
                  maxWidth: tooltipWidth,
                  alignItems: 'center',
                  shadowColor: '#000',
                  shadowOffset: { width: 0, height: 4 },
                  shadowOpacity: 0.3,
                  shadowRadius: 8,
                  elevation: 1000,
                  zIndex: 9999,
                }}
              >
                <Text
                  style={{
                    color: '#F8FAFC',
                    fontWeight: '600',
                    fontFamily: 'monospace',
                    fontSize: 14,
                    textAlign: 'center',
                  }}
                >
                  {`${validLabels[activePointIndex]}: ${gpaPoints[activePointIndex].toFixed(2)}`}
                </Text>
              </View>
            );
          })()}
        {/* Dynamic GPA cards */}
        <View className="flex-1">
          {(() => {
            const fallback: GPAData = { unweighted: 100, weighted: 100 };
            const exists = (label: string) => !!mockGPAData[label];
            const getLabelData = (label: string) => mockGPAData[label] || fallback;

            const renderCard = (label1: string, label2?: string) => (
              <View className="flex-row justify-between mb-3" key={`${label1}-${label2 || "solo"}`}>
                {[label1, label2].filter(Boolean).map(label => (
                  <View key={label} className="bg-cardColor rounded-xl px-3 py-2 w-[48%]">
                    <Text className="text-main font-semibold text-sm mb-1">{label}</Text>
                    <View className="flex-row justify-between">
                      <View className="items-start">
                        <Text className="text-secondary text-xs">Unweighted</Text>
                        <Text className="text-main text-sm font-bold">
                          {exists(label!) ? getLabelData(label!).unweighted.toFixed(2) : "--"}
                        </Text>
                      </View>
                      <View className="items-end">
                        <Text className="text-secondary text-xs">Weighted</Text>
                        <Text className="text-main text-sm font-bold">
                          {exists(label!) ? getLabelData(label!).weighted.toFixed(2) : "--"}
                        </Text>
                      </View>
                    </View>
                  </View>
                ))}
              </View>
            );

            const renderSoloCard = (label: string) => (
              <View className="bg-cardColor rounded-xl px-4 py-3 flex-row items-center justify-between mb-5" key={label}>
                <Text className="text-main font-bold text-lg">{label}</Text>
                <View className="flex-row items-center space-x-6">
                  <View className="items-center">
                    <Text className="text-secondary text-xs mr-3">Unweighted</Text>
                    <Text className="text-main text-lg font-bold">
                      {exists(label) ? getLabelData(label).unweighted.toFixed(2) : "--"}
                    </Text>
                  </View>
                  <View className="items-center">
                    <Text className="text-secondary text-xs">Weighted</Text>
                    <Text className="text-main text-lg font-bold">
                      {exists(label) ? getLabelData(label).weighted.toFixed(2) : "--"}
                    </Text>
                  </View>
                </View>
              </View>
            );

            // Map PRs to their RC group
            const prToRCMap: Record<string, string> = {
              PR1: 'RC1', PR2: 'RC1',
              PR3: 'RC2', PR4: 'RC2',
              PR5: 'RC3', PR6: 'RC3',
              PR7: 'RC4', PR8: 'RC4',
            };

            const rows: JSX.Element[] = [];

            const rcGroups = [
              { rcLabels: ['RC1', 'RC2'], prLabels: ['PR1', 'PR2', 'PR3', 'PR4'] },
              { rcLabels: ['RC3', 'RC4'], prLabels: ['PR5', 'PR6', 'PR7', 'PR8'] }
            ];

            // Find all valid PRs across both groups, get the 2 most recent overall
            const allPRLabels = rcGroups.flatMap(({ prLabels }) => prLabels);
            const validAllPRs = allPRLabels.filter(pr => exists(pr));
            // Only keep the 2 most recent PRs globally
            const latestTwoPRs = validAllPRs.slice(-2);

            // Determine which RC group(s) these PRs belong to
            const rcGroupMap: Record<string, number> = {
              PR1: 0, PR2: 0, PR3: 0, PR4: 0,
              PR5: 1, PR6: 1, PR7: 1, PR8: 1
            };

            // Which RC group index the latest PRs belong to
            const latestGroups = [...new Set(latestTwoPRs.map(pr => rcGroupMap[pr]))];

            // Helper to render RCs in a group, skipping any RC already handled
            const handledRCs = new Set<string>();

            rcGroups.forEach(({ rcLabels, prLabels }, idx) => {
              // If this group is the group of the latest PRs, render only the latest PRs and their RC
              if (latestGroups.includes(idx)) {
                // Among the latestTwoPRs, select those belonging to this group
                const latestGroupPRs = latestTwoPRs.filter(pr => rcGroupMap[pr] === idx);

                // Map PRs to their RC
                const prByRC: Record<string, string[]> = {};
                latestGroupPRs.forEach(pr => {
                  const rc = prToRCMap[pr];
                  if (!prByRC[rc]) prByRC[rc] = [];
                  prByRC[rc].push(pr);
                });
                // For each RC in this group, if it has PRs, render the PR cards
                const prList = [
                  ...(prByRC[rcLabels[0]] || []),
                  ...(prByRC[rcLabels[1]] || [])
                ];
                if (prList && prList.length > 0) {
                  if (prList.length === 2 && 
                    !prList.includes("PR3") &&
                    !prList.includes("PR4") && 
                    !prList.includes("PR7") && 
                    !prList.includes("PR8")) {
                    rows.push(renderCard(prList[0], prList[1]));
                  } else if (prList.length === 1 && (
                    !prList.includes("PR4") && 
                    !prList.includes("PR8")
                  )) {
                    rows.push(renderSoloCard(prList[0]));
                  }
                  
                  if (prList.length === 2 && 
                    (
                      (
                        prList.includes("PR3") &&
                        prList.includes("PR4")
                      ) ||
                      (
                        prList.includes("PR7") &&
                        prList.includes("PR8")
                      )
                    )) {
                    rows.push(renderCard(rcLabels[0], rcLabels[1]));
                    handledRCs.add(rcLabels[idx]);
                    // rows.push(renderCard(prList[0], prList[1]));
                    rows.push(renderCard(prList[0], prList[1]));
                    handledRCs.add(rcLabels[idx+1]);
                  } else {
                    // Render the RC after its PRs
                    rows.push(renderCard(rcLabels[0], rcLabels[1]));
                    handledRCs.add(rcLabels[idx]);
                    handledRCs.add(rcLabels[idx+1]);
                  }
                } 
              } else {
                // For groups NOT containing the latest PRs: render RCs in pairs, unless one is already handled
                const unhandledRCs = rcLabels.filter(rc => !handledRCs.has(rc));
                if (unhandledRCs.length === 2) {
                  rows.push(renderCard(unhandledRCs[0], unhandledRCs[1]));
                } else if (unhandledRCs.length === 1) {
  
                  rows.push(renderSoloCard(unhandledRCs[0]));
                }
              }
              // Render SM1/SM2 as before
              if (idx === 0) {
                rows.push(renderSoloCard('SM1'));
              }
              if (idx === 1) {
                rows.push(renderSoloCard('SM2'));
              }
            });

            const sm1 = exists('SM1') ? getLabelData('SM1') : fallback;
            const sm2 = exists('SM2') ? getLabelData('SM2') : fallback;
            const finUnweighted = (sm1.unweighted + sm2.unweighted) / 2;
            const finWeighted = (sm1.weighted + sm2.weighted) / 2;

            rows.push(
              <View className="bg-cardColor rounded-xl px-4 py-3 flex-row items-center justify-between mb-5" key="FIN">
                <Text className="text-main font-bold text-lg">FIN</Text>
                <View className="flex-row items-center space-x-6">
                  <View className="items-center">
                    <Text className="text-secondary text-xs mr-3">Unweighted</Text>
                    <Text className="text-main text-lg font-bold">{finUnweighted.toFixed(2)}</Text>
                  </View>
                  <View className="items-center">
                    <Text className="text-secondary text-xs">Weighted</Text>
                    <Text className="text-main text-lg font-bold">{finWeighted.toFixed(2)}</Text>
                  </View>
                </View>
              </View>
            );

            return rows;
          })()}
        </View>
              </View>
      </ScrollView>
    );
    };

  const isCurrentGrade = selectedGrade === currentGradeLevel;
  const isPastGrade = gradeLevels.indexOf(selectedGrade) < gradeLevels.indexOf(currentGradeLevel);

  return (
    <View className="flex-1 bg-primary">
      {/* Header */}
      <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
        <Text className="text-white text-3xl font-bold">Grade Point Average</Text>
        <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
          <Ionicons name='cog-outline' color={'#fff'} size={26} />
        </TouchableOpacity>
      </View>

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


      <View className="flex-1 bg-primary">
        {isPastGrade ? renderPDFUploadSection() : renderGPADisplay()}
      </View>
    </View>
  );
};

export default GPA;