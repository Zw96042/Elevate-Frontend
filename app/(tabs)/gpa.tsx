import { useSettingSheet } from '@/context/SettingSheetContext';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from 'expo-router';
import { DeviceEventEmitter } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { MotiView } from 'moti';
import React, { JSX, useCallback, useState, useEffect } from 'react';
import { Alert, Dimensions, PanResponder, ScrollView, Text, TouchableOpacity, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Path, Stop } from 'react-native-svg';
import GradeLevelSelector from '@/components/GradeLevelSelector';
import ManualGradeEntryCard from '@/components/ManualGradeEntryCard';
import { GpaCard, GpaSoloCard } from '@/components/GpaCard';
import { useGradeLevel } from '@/hooks/useGradeLevel';
import { calculateTermGPAs } from '@/utils/gpaCalculator';

type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

interface GPAData {
  unweighted: number;
  weighted: number;
}

const gpaScale = 100; // Change this to 4, 5, etc. as needed

const GPA = () => {
  const { settingSheetRef } = useSettingSheet();
  const [hasCredentials, setHasCredentials] = useState(false);
  const [selectedGrade, setSelectedGrade] = useState<GradeLevel>('Freshman');
  const [activePointIndex, setActivePointIndex] = useState<number | null>(null);
  const [hoverX, setHoverX] = useState<number | null>(null);
  const [isGraphAnimating, setIsGraphAnimating] = useState(false);
  const [savedClasses, setSavedClasses] = useState<any[] | null>(null);
const gpaData = React.useMemo<Record<string, GPAData>>(() => {
  return savedClasses ? calculateTermGPAs(savedClasses) : {};
}, [savedClasses]);
  console.log(gpaData);
    
  // Use extracted hook for current grade level
  const currentGradeLevel = useGradeLevel();
  
  const allLabels = ['PR1','PR2','RC1','PR3','PR4','RC2','PR5','PR6','RC3','PR7','PR8','RC4'];

  const validLabels = allLabels.filter(label => gpaData[label] && gpaData[label].weighted > 0);

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
      // no need to loadGradeLevel or subscribe, handled by useGradeLevel hook
    }, [])
  );

    const renderGPAGraph = () => {
    const screenWidth = Dimensions.get('window').width;
    const graphWidth = screenWidth - 42; 
    const graphHeight = 100;
    const containerWidth = screenWidth - 24; 

    const gpaPoints = validLabels.map(label => gpaData[label]?.weighted ?? 0);

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
    const minGPA = Math.min(...gpaPoints);
    const maxGPA = Math.max(...gpaPoints);
    const dynamicRange = Math.max(maxGPA - minGPA, 1); // Prevent divide by zero

    const normalizedPoints = gpaPoints.map((gpa, index) => {
      const x = (index / numSegments) * graphWidth;
      const y = 10 + ((maxGPA - gpa) / dynamicRange) * (graphHeight - 20);
      return { x, y };
    });
    const segmentWidth = graphWidth / (gpaPoints.length - 1);

    let dotX = null;
    let dotY = null;
    let snappedIndex = null;
    if (hoverX !== null) {
      let x = Math.max(0, Math.min(hoverX, graphWidth));
      if (x <= 0) {
        dotX = normalizedPoints[0].x;
        dotY = normalizedPoints[0].y;
        snappedIndex = 0;
      } else if (x >= graphWidth) {
        dotX = normalizedPoints[normalizedPoints.length - 1].x;
        dotY = normalizedPoints[normalizedPoints.length - 1].y;
        snappedIndex = gpaPoints.length - 1;
      } else {
        const leftIdx = Math.floor(x / segmentWidth);
        const rightIdx = Math.min(leftIdx + 1, normalizedPoints.length - 1);
        const p0 = normalizedPoints[leftIdx];
        const p1 = normalizedPoints[rightIdx];
        const cp1 = { x: p0.x + (p1.x - p0.x) * 0.3, y: p0.y };
        const cp2 = { x: p1.x - (p1.x - p0.x) * 0.3, y: p1.y };
        const t = (x - leftIdx * segmentWidth) / segmentWidth;
        const u = 1 - t;
        dotX = u * u * u * p0.x
             + 3 * u * u * t * cp1.x
             + 3 * u * t * t * cp2.x
             + t * t * t * p1.x;
        dotY = u * u * u * p0.y
             + 3 * u * u * t * cp1.y
             + 3 * u * t * t * cp2.y
             + t * t * t * p1.y;
        const midpoint = (normalizedPoints[leftIdx].x + normalizedPoints[rightIdx].x) / 2;
        snappedIndex = x < midpoint ? leftIdx : rightIdx;
      }
    } else if (activePointIndex !== null) {
      dotX = normalizedPoints[activePointIndex].x;
      dotY = normalizedPoints[activePointIndex].y;
      snappedIndex = activePointIndex;
    }

    const panResponder = PanResponder.create({
      onStartShouldSetPanResponder: () => !isGraphAnimating,
      onPanResponderGrant: (evt) => {
        if (isGraphAnimating) return;
        const x = evt.nativeEvent.locationX;
        setHoverX(x);
      },
      onPanResponderMove: (evt) => {
        if (isGraphAnimating) return;
        const x = evt.nativeEvent.locationX;
        setHoverX(x);
      },
      onPanResponderRelease: () => {
        if (isGraphAnimating) return;
        setHoverX(null);
        setActivePointIndex(null);
      },
      onPanResponderTerminate: () => {
        if (isGraphAnimating) return;
        setHoverX(null);
        setActivePointIndex(null);
      }
    });

    const pathData = normalizedPoints.map((point, index) => {
      if (index === 0) return `M ${point.x} ${point.y}`;
      const prevPoint = normalizedPoints[index - 1];
      const controlX1 = prevPoint.x + (point.x - prevPoint.x) * 0.3;
      const controlY1 = prevPoint.y;
      const controlX2 = point.x - (point.x - prevPoint.x) * 0.3;
      const controlY2 = point.y;
      return `C ${controlX1} ${controlY1} ${controlX2} ${controlY2} ${point.x} ${point.y}`;
    }).join(' ');

    const fillPathData = pathData + ` L ${graphWidth} ${graphHeight + 5} L 0 ${graphHeight} Z`;

    const showDotAndTooltip = (hoverX !== null || activePointIndex !== null) && dotX !== null && dotY !== null && snappedIndex !== null;

    return (
      <View className="mb-4 bg-cardColor rounded-xl pt-4 overflow-hidden relative">
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
              <Path d={pathData} stroke="#0090FF" strokeWidth="2" fill="none" />
              {showDotAndTooltip && (
                <Circle
                  cx={dotX ?? 0}
                  cy={dotY ?? 0}
                  r={5}
                  fill="#0A84FF"
                  stroke="white"
                  strokeWidth={2}
                />
              )}
            </Svg>
          </View>
          <MotiView
            from={{ width: containerWidth }}
            animate={{ width: 0 }}
            transition={{
              type: 'spring',
              damping: 1000,
              mass: 8,
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
            className="bg-cardColor"
            onLayout={() => setIsGraphAnimating(true)}
          />
        </View>
        {showDotAndTooltip && (() => {
          const tooltipWidth = 140;
          const tooltipHeight = 40;
          const padding = 24;
          const graphLeft = padding;
          const edgeBuffer = 25;
          const graphRight = graphLeft + graphWidth;
          const screenX = graphLeft + (dotX ?? 0);
          let left = screenX - (tooltipWidth / 2);
          let top = dotY ?? 0;
          if (left + tooltipWidth > graphRight + 15) left = graphRight + 15 - tooltipWidth;
          if (left < graphLeft - edgeBuffer) left = graphLeft - edgeBuffer;
          const screenHeight = Dimensions.get('window').height;
          if (top + tooltipHeight > screenHeight - 100) {
            top = (dotY ?? 0) - tooltipHeight - 20;
          }
          const safeIndex = snappedIndex ?? 0;
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
                {`${validLabels[safeIndex]}: ${gpaPoints[safeIndex].toFixed(2)}`}
              </Text>
            </View>
          );
        })()}
      </View>
    );
  };


  const renderGPADisplay = (showPrs : Boolean) => {
    const screenWidth = Dimensions.get('window').width;
    const graphWidth = screenWidth - 42; 
    const graphHeight = 100;
    const gpaPoints = validLabels.map(label => gpaData[label]?.weighted ?? 0);
    
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
          
          {activePointIndex !== null && gpaPoints.length >= 2 && (() => {
            const tooltipWidth = 140; 
            const tooltipHeight = 40; 
            const padding = 24;
            
            const actualScreenWidth = Dimensions.get('window').width;
            const graphWidth = actualScreenWidth - 42; 
            
            const graphLeft = padding;
            const graphRight = graphLeft + graphWidth - 10;
            
            const screenX = graphLeft + normalizedPoints[activePointIndex].x;
            let left = screenX - (tooltipWidth / 2); 
            let top = normalizedPoints[activePointIndex].y;
            
            if (left + tooltipWidth > graphRight + 55) {
              const overshoot = (left + tooltipWidth) - (graphRight + 55);
              left = left - overshoot - 10;
            }
            
            if (left < graphLeft) {
              left = graphLeft;
            }
            const screenHeight = Dimensions.get('window').height;
            if (top + tooltipHeight > screenHeight - 100) {
              top = normalizedPoints[activePointIndex].y - tooltipHeight - 20;
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
        <View className="flex-1">
          {(() => {
            const fallback: GPAData = { unweighted: 100, weighted: 100 };
            const exists = (label: string) => !!gpaData[label];
            const getLabelData = (label: string) => gpaData[label] || fallback;

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
            const allPRLabels = rcGroups.flatMap(({ prLabels }) => prLabels);
            const validAllPRs = allPRLabels.filter(pr => exists(pr));

            const latestTwoPRs = validAllPRs.slice(-2);

            const rcGroupMap: Record<string, number> = {
              PR1: 0, PR2: 0, PR3: 0, PR4: 0,
              PR5: 1, PR6: 1, PR7: 1, PR8: 1
            };

            const latestGroups = [...new Set(latestTwoPRs.map(pr => rcGroupMap[pr]))];

            const handledRCs = new Set<string>();

            rcGroups.forEach(({ rcLabels, prLabels }, idx) => {
              if (latestGroups.includes(idx)) {
                const latestGroupPRs = latestTwoPRs.filter(pr => rcGroupMap[pr] === idx);

                const prByRC: Record<string, string[]> = {};
                latestGroupPRs.forEach(pr => {
                  const rc = prToRCMap[pr];
                  if (!prByRC[rc]) prByRC[rc] = [];
                  prByRC[rc].push(pr);
                });
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
                    rows.push(
                      <View className="flex-row justify-between mb-3" key={`${prList[0]}-${prList[1]}`}>
                        <GpaCard label={prList[0]} data={getLabelData(prList[0])} />
                        <GpaCard label={prList[1]} data={getLabelData(prList[1])} />
                      </View>
                    );
                  } else if (prList.length === 1 && (
                    !prList.includes("PR4") && 
                    !prList.includes("PR8")
                  )) {
                    rows.push(
                      <GpaSoloCard key={prList[0]} label={prList[0]} data={getLabelData(prList[0])} />
                    );
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
                    rows.push(
                      <View className="flex-row justify-between mb-3" key={`${rcLabels[0]}-${rcLabels[1]}`}>
                        <GpaCard label={rcLabels[0]} data={getLabelData(rcLabels[0])} />
                        <GpaCard label={rcLabels[1]} data={getLabelData(rcLabels[1])} />
                      </View>
                    );
                    handledRCs.add(rcLabels[idx]);
                    if (showPrs) {
                      rows.push(
                        <View className="flex-row justify-between mb-3" key={`${prList[0]}-${prList[1]}-extra`}>
                          <GpaCard label={prList[0]} data={getLabelData(prList[0])} />
                          <GpaCard label={prList[1]} data={getLabelData(prList[1])} />
                        </View>
                      );
                    } 
                    handledRCs.add(rcLabels[idx+1])
                    
                  } else {
                    rows.push(
                      <View className="flex-row justify-between mb-3" key={`${rcLabels[0]}-${rcLabels[1]}`}>
                        <GpaCard label={rcLabels[0]} data={getLabelData(rcLabels[0])} />
                        <GpaCard label={rcLabels[1]} data={getLabelData(rcLabels[1])} />
                      </View>
                    );
                    handledRCs.add(rcLabels[idx]);
                    handledRCs.add(rcLabels[idx+1]);
                  }
                } 
              } else {
                const unhandledRCs = rcLabels.filter(rc => !handledRCs.has(rc));
                if (unhandledRCs.length === 2) {
                  rows.push(
                    <View className="flex-row justify-between mb-3" key={`${unhandledRCs[0]}-${unhandledRCs[1]}`}>
                      <GpaCard label={unhandledRCs[0]} data={getLabelData(unhandledRCs[0])} />
                      <GpaCard label={unhandledRCs[1]} data={getLabelData(unhandledRCs[1])} />
                    </View>
                  );
                } else if (unhandledRCs.length === 1) {
                  rows.push(
                    <GpaSoloCard key={unhandledRCs[0]} label={unhandledRCs[0]} data={getLabelData(unhandledRCs[0])} />
                  );
                }
              }
              if (idx === 0) {
                rows.push(
                  <GpaSoloCard key="SM1" label="SM1" data={getLabelData('SM1')} />
                );
              }
              if (idx === 1) {
                rows.push(
                  <GpaSoloCard key="SM2" label="SM2" data={getLabelData('SM2')} />
                );
              }
            });

            const sm1 = exists('SM1') ? getLabelData('SM1') : fallback;
            const sm2 = exists('SM2') ? getLabelData('SM2') : fallback;
            const finUnweighted = (sm1.unweighted + sm2.unweighted) / 2;
            const finWeighted = (sm1.weighted + sm2.weighted) / 2;

            rows.push(
              <GpaSoloCard
                key="FIN"
                label="FIN"
                data={{
                  unweighted: finUnweighted,
                  weighted: finWeighted,
                }}
              />
            );

            if (!showPrs) {
              rows.push(
                <ManualGradeEntryCard
                  key="MANCARD"
                 selectedGrade={selectedGrade} minimized={!!(savedClasses && savedClasses.length > 0)} />
              );
            }

            return rows;
          })()}
        </View>
              </View>
      </ScrollView>
    );
    };

  useEffect(() => {
    if (isGraphAnimating) {
      const timeout = setTimeout(() => {
        setIsGraphAnimating(false);
      }, 600);
      return () => clearTimeout(timeout);
    }
  }, [isGraphAnimating]);


  const prevSelectedGrade = React.useRef<GradeLevel | null>(null);

  useEffect(
    React.useCallback(() => {
      const checkSavedClasses = async () => {
        try {
          const data = await AsyncStorage.getItem(`savedClasses-${selectedGrade}`);
          const parsedData = data ? JSON.parse(data) : null;
          setSavedClasses(prev => {
            if (JSON.stringify(prev) === JSON.stringify(parsedData)) return prev;
            return parsedData;
          });
        } catch (error) {
          console.error('Error reading saved classes:', error);
          setSavedClasses(null);
        }
      };
      checkSavedClasses();
    }, []) // no dependencies, only on focus
  );

  return (
    <View className="flex-1 bg-primary">
      <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
        <Text className="text-white text-3xl font-bold">Grade Point Average</Text>
        <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
          <Ionicons name='cog-outline' color={'#fff'} size={26} />
        </TouchableOpacity>
      </View>

      <View className="mt-4 pb-4 px-4">
        <GradeLevelSelector
          grades={availableGradeLevels}
          selectedGrade={selectedGrade}
          onSelectGrade={setSelectedGrade}
        />
      </View>

      <View className="flex-1 bg-primary">
        {(selectedGrade === 'All Time' || selectedGrade === currentGradeLevel || (savedClasses && savedClasses.length > 0)) ? (
          renderGPADisplay(!(savedClasses && savedClasses.length > 0))
        ) : (
          <ManualGradeEntryCard
            selectedGrade={selectedGrade}
            minimized={!!(savedClasses && savedClasses.length > 0)}
          />
        )}
      </View>
    </View>
  );
};

export default GPA;