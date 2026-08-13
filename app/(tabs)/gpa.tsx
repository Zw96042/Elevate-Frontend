import { useSettingSheet } from '@/context/SettingSheetContext';
import { SkywardAuth, UnifiedGPAManager, type GPAData, type UnifiedCourseData } from '@/lib';
import { Ionicons } from '@expo/vector-icons';
import { MotiView } from 'moti';
import React, { JSX, useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { Dimensions, PanResponder, Text, TouchableOpacity, View, RefreshControl, DeviceEventEmitter } from 'react-native';
import { ScrollView } from 'react-native-gesture-handler'
import Svg, { Circle, Defs, LinearGradient, Path, Stop } from 'react-native-svg';
import GradeLevelSelector from '@/components/GradeLevelSelector';
import SkeletonGradeLevelSelector from '@/components/SkeletonGradeLevelSelector';
import ManualGradeEntryCard from '@/components/ManualGradeEntryCard';
import { GpaCard, GpaSoloCard } from '@/components/GpaCard';
import ErrorDisplay from '@/components/ErrorDisplay';
import LoginPrompt from '@/components/LoginPrompt';
import { useGradeLevel } from '@/hooks/useGradeLevel';
import { useUnifiedData } from '@/context/UnifiedDataContext';
import { useColorScheme } from 'nativewind';
import { shouldEnableShowoffMode } from '@/utils/showoffMode';
import { logger, Modules } from '@/lib/utils/logger';
import { useFocusEffect } from 'expo-router';
import {
  loadAvailableManualGradeLevels,
  loadManualCoursesForSelection,
  mergeAcademicCourses,
  type HistoricalGradeLevel,
} from '@/lib/utils/manual-gpa';
import {
  averageSemesterGPA,
  formatGPAValue,
  isFiniteGPA,
  shouldShowGPALogin,
} from '@/lib/utils/gpa-values';

type GradeLevel = 'Current' | 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

const gpaScale = 100; // Change this to 4, 5, etc. as needed

// Memoized grade map to prevent recreation
const GRADE_MAP: Record<string, number> = {
  'Freshman': 9,
  'Sophomore': 10,
  'Junior': 11,
  'Senior': 12
};

const coursesForGrade = (courses: UnifiedCourseData[], grade: GradeLevel): UnifiedCourseData[] => {
  if (grade === 'All Time') return courses;
  if (grade === 'Current') return courses.filter(course => course.gradeYear == null);
  const gradeNumber = GRADE_MAP[grade];
  return courses.filter(course => course.gradeYear === gradeNumber);
};

const GPA = () => {
  // Use coursesData from context instead of local allRawCourses
  const { settingSheetRef, username, showoffMode } = useSettingSheet();
  const [hasCredentials, setHasCredentials] = useState(false);
  const [hasCheckedCredentials, setHasCheckedCredentials] = useState(false);
  
  // Use extracted hook for current grade level and available grade levels
  const { currentGradeLevel, availableGradeLevels, isLoading: gradeLevelLoading, loadGradeFromCourseData } = useGradeLevel();

  // Move useColorScheme to top level to avoid hook order violations
  const { colorScheme } = useColorScheme();
  
  logger.debug(Modules.PAGE_GPA, 'Grade-level data changed', {
    currentGradeLevel,
    availableGradeLevels,
    gradeLevelLoading
  });
  
  // Initialize selectedGrade with currentGradeLevel instead of 'Freshman'
  const [selectedGrade, setSelectedGrade] = useState<GradeLevel>(currentGradeLevel);
  
  logger.debug(Modules.PAGE_GPA, 'Selected grade changed', { selectedGrade });
  
  // Removed console logging for selectedGrade changes
  const [activePointIndex, setActivePointIndex] = useState<number | null>(null);
  const [hoverX, setHoverX] = useState<number | null>(null);
  const [isGraphAnimating, setIsGraphAnimating] = useState(false);
  const [savedClasses, setSavedClasses] = useState<UnifiedCourseData[]>([]);
  const [manualGradeLevels, setManualGradeLevels] = useState<HistoricalGradeLevel[]>([]);
  const [manualLoading, setManualLoading] = useState(true);
  const manualLoadIDRef = useRef(0);
  const [gpaData, setGpaData] = useState<Record<string, GPAData>>({});
  const { coursesData, loading, refreshCourses } = useUnifiedData();
  
  // Update grade levels when course data becomes available (only once per data change)
  useEffect(() => {
    if (coursesData && coursesData.length > 0) {
      logger.debug(Modules.PAGE_GPA, 'Updating grade levels from course data', {
        coursesCount: coursesData.length,
      });
      loadGradeFromCourseData(coursesData);
    }
  }, [coursesData, loadGradeFromCourseData]);
  const [refreshing, setRefreshing] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);
  const isInteractingWithGraph = useRef(false);
  const hasInitializedGradeRef = useRef(false);
  const userHasManuallySelectedGradeRef = useRef(false); // Track if user manually selected a grade
  const [error, setError] = useState<string | null>(null);

  const loadManualData = useCallback(async () => {
    const loadID = ++manualLoadIDRef.current;
    setManualLoading(true);
    try {
      const [manualCourses, levels] = await Promise.all([
        loadManualCoursesForSelection(selectedGrade),
        loadAvailableManualGradeLevels(),
      ]);
      if (loadID === manualLoadIDRef.current) {
        setSavedClasses(manualCourses);
        setManualGradeLevels(levels);
      }
    } catch (loadError) {
      logger.error(Modules.PAGE_GPA, 'Failed to load manual GPA history', loadError);
      if (loadID === manualLoadIDRef.current) setSavedClasses([]);
    } finally {
      if (loadID === manualLoadIDRef.current) setManualLoading(false);
    }
  }, [selectedGrade]);

  useFocusEffect(useCallback(() => {
    void loadManualData();
  }, [loadManualData]));

  useEffect(() => {
    let active = true;
    void SkywardAuth.hasCredentials()
      .then(result => {
        if (active) setHasCredentials(result);
      })
      .catch(checkError => {
        logger.warn(Modules.PAGE_GPA, 'Unable to check stored credentials', checkError);
      })
      .finally(() => {
        if (active) setHasCheckedCredentials(true);
      });
    return () => { active = false; };
  }, []);

  // Listen for credential updates
  useEffect(() => {
    const credentialsListener = DeviceEventEmitter.addListener('credentialsAdded', async () => {
      // Auto-refresh when credentials are verified
      setError(null);
      setIsInitialized(false);
      userHasManuallySelectedGradeRef.current = false; // Reset manual selection flag
      hasInitializedGradeRef.current = false; // Reset initialization flag
      setHasCredentials(true);
      setHasCheckedCredentials(true);
      void loadManualData();
      // Small delay to ensure AsyncStorage writes have completed
      setTimeout(async () => {
        try {
          await refreshCourses(true);
        } catch (error) {
          logger.error(Modules.PAGE_GPA, 'Failed to refresh after credentials update', error);
          setError('Unable to load GPA data. Please try again.');
        }
      }, 100);
    });
    const invalidCredentialsListener = DeviceEventEmitter.addListener('credentialsInvalid', () => {
      manualLoadIDRef.current += 1;
      setHasCredentials(false);
      setHasCheckedCredentials(true);
      setSavedClasses([]);
      setManualGradeLevels([]);
      setGpaData({});
      setManualLoading(false);
    });

    return () => {
      credentialsListener.remove();
      invalidCredentialsListener.remove();
    };
  }, [loadManualData, refreshCourses]);
  
  // Update selectedGrade when currentGradeLevel changes, but only on initial load
  useEffect(() => {
    logger.debug(Modules.PAGE_GPA, 'Evaluating selected-grade synchronization', {
      currentGradeLevel,
      selectedGrade,
      hasInitializedGradeRef: hasInitializedGradeRef.current,
      userHasManuallySelectedGrade: userHasManuallySelectedGradeRef.current,
      gradeLevelLoading
    });
    
    // Only auto-update selectedGrade if user hasn't manually selected a grade
    // and the grade level data has finished loading
    if (!userHasManuallySelectedGradeRef.current && !gradeLevelLoading && currentGradeLevel !== selectedGrade) {
      logger.debug(Modules.PAGE_GPA, 'Synchronizing selected grade', { currentGradeLevel });
      setSelectedGrade(currentGradeLevel);
      hasInitializedGradeRef.current = true;
    }
  }, [currentGradeLevel, selectedGrade, gradeLevelLoading]);
  
  const allLabels = useMemo(() => ['PR1','PR2','RC1','PR3','PR4','RC2','PR5','PR6','RC3','PR7','PR8','RC4'], []);

  const displayedGradeLevels = useMemo<GradeLevel[]>(() => {
    const levels = new Set<GradeLevel>(availableGradeLevels);
    manualGradeLevels.forEach(level => levels.add(level));
    const ordered: GradeLevel[] = ['Current', 'Freshman', 'Sophomore', 'Junior', 'Senior'];
    const result = ordered.filter(level => levels.has(level));
    if (result.length > 1 || levels.has('All Time')) result.push('All Time');
    return result.length > 0 ? result : [currentGradeLevel];
  }, [availableGradeLevels, currentGradeLevel, manualGradeLevels]);

  const selectedCourses = useMemo(() => mergeAcademicCourses(
    coursesForGrade(coursesData ?? [], selectedGrade),
    savedClasses
  ), [coursesData, savedClasses, selectedGrade]);

  // Memoize valid labels calculation
  const validLabels = useMemo(() => {
    return allLabels.filter(label => {
      const gpaValue = gpaData[label];
      return isFiniteGPA(gpaValue);
    });
  }, [allLabels, gpaData]);


  // Removed leftover loadGPAData logic. Use context and local derived state only.

  // Function for pull-to-refresh
  const onRefresh = async () => {
    setRefreshing(true);
    setError(null); // Clear any existing errors
    const wasInteracting = isInteractingWithGraph.current;
    isInteractingWithGraph.current = false;
    try {
      // A forced fetch already bypasses the cache. Keep the current snapshot so
      // an offline refresh cannot erase the last useful GPA view.
      await refreshCourses(true);
      await loadManualData();
    } catch (error) {
      logger.error(Modules.PAGE_GPA, 'Failed to refresh GPA data', error);
      setError('Unable to refresh GPA data. Please check your connection and try again.');
    } finally {
      setRefreshing(false);
      isInteractingWithGraph.current = wasInteracting;
    }
  };

  // Calculate from both Skyward and account-scoped manual history. This also
  // initializes a manual-only GPA without waiting for a network login.
  useEffect(() => {
    if (gradeLevelLoading || manualLoading) return;
    setGpaData(UnifiedGPAManager.calculateCurrentGradeGPA(
      selectedCourses,
      showoffMode && shouldEnableShowoffMode(username),
      username
    ));
    setIsInitialized(true);
  }, [gradeLevelLoading, manualLoading, selectedCourses, showoffMode, username]);

  // Handle grade selection changes
  const handleGradeChange = useCallback((newGrade: GradeLevel) => {
    logger.debug(Modules.PAGE_GPA, 'Grade selection changed', {
      from: selectedGrade,
      to: newGrade
    });
    userHasManuallySelectedGradeRef.current = true; // Mark that user manually selected
    setSelectedGrade(newGrade);
    setActivePointIndex(null);
    setHoverX(null);
  }, [selectedGrade]);

  const renderGPAGraph = useCallback(() => {
    const screenWidth = Dimensions.get('window').width;
    const graphWidth = screenWidth - 42; 
    const graphHeight = 100;
    // const containerWidth = screenWidth - 24; 

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
        isInteractingWithGraph.current = true; // Block API calls
        const x = evt.nativeEvent.locationX;
        setHoverX(x);
      },
      onPanResponderMove: (evt) => {
        if (isGraphAnimating) return;
        isInteractingWithGraph.current = true; // Block API calls
        const x = evt.nativeEvent.locationX;
        setHoverX(x);
      },
      onPanResponderRelease: () => {
        if (isGraphAnimating) return;
        setHoverX(null);
        setActivePointIndex(null);
        // Delay clearing the flag to prevent any immediate re-renders from triggering API calls
        setTimeout(() => {
          isInteractingWithGraph.current = false;
        }, 100);
      },
      onPanResponderTerminate: () => {
        if (isGraphAnimating) return;
        setHoverX(null);
        setActivePointIndex(null);
        // Delay clearing the flag to prevent any immediate re-renders from triggering API calls
        setTimeout(() => {
          isInteractingWithGraph.current = false;
        }, 100);
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

    const cardColor = colorScheme === 'dark' ? '#1f2937' : '#fafafa';

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
            from={{ width: '100%' }}
            animate={{ width: '0%' }}
            transition={{
              type: 'spring',
              damping: 35,
              mass: 6,
              stiffness: 60,
            }}
            style={{
              position: 'absolute',
              top: 0,
              bottom: 0,
              right: 0,
              backgroundColor: cardColor,
              zIndex: 10,
            }}
            onDidAnimate={(key, finished) => {
              if (key === 'width' && finished) {
                setIsGraphAnimating(false);
              }
            }}
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
                backgroundColor: colorScheme === 'dark' ? 'rgba(30, 41, 59, 0.95)' : 'rgba(255, 255, 255, 0.95)',
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
                  color: colorScheme === 'dark' ? '#F8FAFC' : '#1F2937',
                  fontWeight: '600',
                  fontFamily: 'monospace',
                  fontSize: 14,
                  textAlign: 'center',
                }}
              >
                {`${validLabels[safeIndex]}: ${formatGPAValue(gpaPoints[safeIndex])}`}
              </Text>
            </View>
          );
        })()}
      </View>
    );
  }, [validLabels, gpaData, hoverX, activePointIndex, isGraphAnimating, colorScheme]);


  const renderGPADisplay = (showPrs: boolean) => {
    // Function to determine if we should show specific PR pairs
    const shouldShowPRPair = (prPair: string[]) => {
      // Check if we have data for the PR pair
      const hasPRData = prPair.every(pr => isFiniteGPA(gpaData[pr]));
      
      if (!hasPRData) return false; // Don't show if we don't have PR data
      
      // Check if FIN card exists (both SM1 and SM2 have data)
      const hasFINCard = gpaData['SM1'] !== undefined && gpaData['SM2'] !== undefined;
      if (hasFINCard) {
        return false; // Don't show PR cards if FIN card exists
      }
      
      // Determine what comes after the RC/SM that follows this PR pair
      let nextPeriods: string[] = [];
      if (prPair.includes('PR3') && prPair.includes('PR4')) {
        // After PR3/PR4 -> RC2/SM1 -> then PR5/PR6/RC3
        nextPeriods = ['PR5', 'PR6', 'RC3']; 
      } else if (prPair.includes('PR7') && prPair.includes('PR8')) {
        // After PR7/PR8 -> RC4/SM2 -> then PR9/PR10/RC5 (if they exist)
        nextPeriods = ['PR9', 'PR10', 'RC5']; 
      }
      
      // Check if we DON'T have data for the periods that come after the RC/SM
      const hasNextPeriodData = nextPeriods.some(period => isFiniteGPA(gpaData[period]));
      
      // Show PRs only if we have PR data but NO data for what comes after the RC/SM
      return !hasNextPeriodData;
    };
    
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
      <ScrollView 
        className="flex-1" 
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor="#FFFFFF"
            colors={['#FFFFFF']}
          />
        }
      >
        <View className="px-6">
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
                  backgroundColor: colorScheme === 'dark' ? 'rgba(30, 41, 59, 0.95)' : 'rgba(255, 255, 255, 0.95)',
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
                    color: colorScheme === 'dark' ? '#F8FAFC' : '#1F2937',
                    fontWeight: '600',
                    fontFamily: 'monospace',
                    fontSize: 14,
                    textAlign: 'center',
                  }}
                >
                  {`${validLabels[activePointIndex]}: ${formatGPAValue(gpaPoints[activePointIndex])}`}
                </Text>
              </View>
            );
          })()}
        <View className="flex-1">
          {(() => {
            const fallback: GPAData = { unweighted: 0, weighted: 0 }; // Changed from 100 to 0
            const exists = (label: string) => gpaData[label] !== undefined;
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
                  // Check if FIN card exists (both SM1 and SM2 have data)
                  const hasFINCard = exists('SM1') && exists('SM2');
                  
                  if (prList.length === 2 && 
                    !prList.includes("PR3") &&
                    !prList.includes("PR4") && 
                    !prList.includes("PR7") && 
                    !prList.includes("PR8") &&
                    !hasFINCard) { // Don't show PR cards if FIN card exists
                    rows.push(
                      <View className="flex-row justify-between mb-3" key={`${prList[0]}-${prList[1]}`}>
                        <GpaCard label={prList[0]} data={getLabelData(prList[0])} />
                        <GpaCard label={prList[1]} data={getLabelData(prList[1])} />
                      </View>
                    );
                  } else if (prList.length === 1 && (
                    !prList.includes("PR4") && 
                    !prList.includes("PR8")
                  ) && !hasFINCard) { // Don't show PR cards if FIN card exists
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
                    // Use the new logic for this specific PR pair
                    const shouldShowThisPRPair = shouldShowPRPair(prList);
                    
                    if (shouldShowThisPRPair) {
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

            const finalGPA = averageSemesterGPA(gpaData.SM1, gpaData.SM2) ?? fallback;

            if (exists('SM1') && exists('SM2')) {
              rows.push(
                <GpaSoloCard
                  key="FIN"
                  label="FIN"
                  data={{
                    unweighted: finalGPA.unweighted,
                    weighted: finalGPA.weighted,
                  }}
                />
              );
            }
            if (!showPrs && selectedGrade !== 'Current' && selectedGrade !== 'All Time') {
              rows.push(
                <ManualGradeEntryCard
                  key={`MANCARD-${selectedGrade}`}
                  selectedGrade={selectedGrade}
                  minimized={Object.keys(gpaData).length > 0 || savedClasses.length > 0}
                  rawCourses={coursesData}
                />
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

  // Show error display if there's an error
  if (error && !coursesData && savedClasses.length === 0) {
    return (
      <View className="flex-1 bg-primary">
        <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
          <Text className="text-white text-3xl font-bold">Grade Point Average</Text>
          <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
            <Ionicons name='cog-outline' color={'#fff'} size={26} />
          </TouchableOpacity>
        </View>
        <View className="flex-1 mt-24">
          <ErrorDisplay
            error={error}
            onRetry={async () => {
              setError(null);
              setIsInitialized(false);
              try {
                await refreshCourses(true);
              } catch {
                setError('Unable to load GPA data. Please try again.');
              }
            }}
            title="Couldn't load GPA data"
          />
        </View>
      </View>
    );
  }

  // Show login prompt if credentials are not set (but only after we've checked)
  if (shouldShowGPALogin({
    checkedCredentials: hasCheckedCredentials,
    hasCredentials,
    loadingCourses: loading,
    hasCourseSnapshot: coursesData !== null,
    manualYearCount: manualGradeLevels.length,
  })) {
    return (
      <View className="flex-1 bg-primary">
        <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
          <Text className="text-white text-3xl font-bold">Grade Point Average</Text>
          <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
            <Ionicons name='cog-outline' color={'#fff'} size={26} />
          </TouchableOpacity>
        </View>
        <View className="flex-1 mt-20">
          <LoginPrompt
            message="Please log in with your Skyward credentials to view your GPA."
            onLoginPress={() => settingSheetRef.current?.snapToIndex(0)}
          />
        </View>
      </View>
    );
  }

  // Show loading state while initializing or loading data
  const isLoadingState = (loading && !coursesData && savedClasses.length === 0)
    || gradeLevelLoading || manualLoading || !isInitialized;

  return (
    <View className="flex-1 bg-primary">
      <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
        <Text className="text-white text-3xl font-bold">Grade Point Average</Text>
        <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
          <Ionicons name='cog-outline' color={'#fff'} size={26} />
        </TouchableOpacity>
      </View>

      <View className="mt-4 pb-4 px-4">
        {gradeLevelLoading ? (
          <SkeletonGradeLevelSelector />
        ) : (
          <GradeLevelSelector
            grades={displayedGradeLevels}
            selectedGrade={selectedGrade}
            onSelectGrade={handleGradeChange}
          />
        )}
      </View>

      <View className="flex-1 bg-primary">
        {isLoadingState ? (
          <View className="flex-1 justify-center items-center">
            <Text className="text-main text-lg">Loading academic history...</Text>
          </View>
        ) : (selectedGrade === 'All Time' || selectedGrade === currentGradeLevel || (Object.keys(gpaData).length > 0 || savedClasses.length > 0)) ? (
          (() => {
            const hasGpaData = Object.keys(gpaData).length > 0;
            const hasSavedClasses = savedClasses.length > 0;
            const showPrsValue = !(hasGpaData || hasSavedClasses);
            
            return renderGPADisplay(showPrsValue);
          })()
        ) : (
          <ManualGradeEntryCard
            key={`MANCARD-${selectedGrade}`}
            selectedGrade={selectedGrade}
            minimized={!!(Object.keys(gpaData).length > 0 || savedClasses.length > 0)}
            rawCourses={coursesData}
          />
        )}
      </View>
    </View>
  );
}

export default React.memo(GPA);
