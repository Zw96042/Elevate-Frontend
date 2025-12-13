import { useSettingSheet } from '@/context/SettingSheetContext';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { Ionicons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { MotiView } from 'moti';
import React, { JSX, useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { Alert, Dimensions, PanResponder, Text, TouchableOpacity, View, RefreshControl, DeviceEventEmitter } from 'react-native';
import { ScrollView } from 'react-native-gesture-handler'
import Svg, { Circle, Defs, LinearGradient, Path, Stop } from 'react-native-svg';
import GradeLevelSelector from '@/components/GradeLevelSelector';
import SkeletonGradeLevelSelector from '@/components/SkeletonGradeLevelSelector';
import ManualGradeEntryCard from '@/components/ManualGradeEntryCard';
import { GpaCard, GpaSoloCard } from '@/components/GpaCard';
import ErrorDisplay from '@/components/ErrorDisplay';
import LoginPrompt from '@/components/LoginPrompt';
import { useGradeLevel } from '@/hooks/useGradeLevel';
import { UnifiedGPAManager, GPAData } from '@/lib/unifiedGpaManager';
import { UnifiedCourseData } from '@/lib/unifiedDataManager';
import { useUnifiedData } from '@/context/UnifiedDataContext';
import { useColorScheme } from 'nativewind';

type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

const gpaScale = 100; // Change this to 4, 5, etc. as needed

// Helper function to convert grade level names to numbers - memoized
const getGradeNumber = (gradeLevel: GradeLevel): number | undefined => {
  switch (gradeLevel) {
    case 'Freshman': return 9;
    case 'Sophomore': return 10;
    case 'Junior': return 11;
    case 'Senior': return 12;
    case 'All Time': return undefined; // All grades
    default: return undefined;
  }
};

// Memoized grade map to prevent recreation
const GRADE_MAP: Record<string, number> = {
  'Freshman': 9,
  'Sophomore': 10,
  'Junior': 11,
  'Senior': 12
};

const GPA = () => {
  // Use coursesData from context instead of local allRawCourses
  const { settingSheetRef } = useSettingSheet();
  const [hasCredentials, setHasCredentials] = useState(false);
  
  // Use extracted hook for current grade level and available grade levels
  const { currentGradeLevel, availableGradeLevels, isLoading: gradeLevelLoading, refreshGradeLevelData, debugCacheState, clearGradeLevelCache, loadGradeFromCourseData } = useGradeLevel();

  // Move useColorScheme to top level to avoid hook order violations
  const { colorScheme } = useColorScheme();
  
  console.log('🎨 GPA Component - Grade level data:', {
    currentGradeLevel,
    availableGradeLevels,
    gradeLevelLoading
  });
  
  // Initialize selectedGrade with currentGradeLevel instead of 'Freshman'
  const [selectedGrade, setSelectedGrade] = useState<GradeLevel>(currentGradeLevel);
  
  console.log('🎨 GPA Component - selectedGrade state:', selectedGrade);
  
  // Debug cache state on mount
  useEffect(() => {
    console.log('🔍 GPA Component mounted, debugging cache state...');
    debugCacheState();
  }, [debugCacheState]);
  
  // Removed console logging for selectedGrade changes
  const [activePointIndex, setActivePointIndex] = useState<number | null>(null);
  const [hoverX, setHoverX] = useState<number | null>(null);
  const [isGraphAnimating, setIsGraphAnimating] = useState(false);
  const [savedClasses, setSavedClasses] = useState<any[] | null>(null);
  const [gpaData, setGpaData] = useState<Record<string, GPAData>>({});
  const { coursesData, loading, refreshCourses, clearCache } = useUnifiedData();
  
  // Update grade levels when course data becomes available (only once per data change)
  useEffect(() => {
    if (coursesData && coursesData.length > 0 && !gradeLevelLoading) {
      console.log('📊 Course data available, updating grade levels...', {
        coursesCount: coursesData.length,
        gradeLevelLoading
      });
      loadGradeFromCourseData(coursesData);
    }
  }, [coursesData?.length, gradeLevelLoading]); // Remove loadGradeFromCourseData dependency to prevent infinite loop
  const [refreshing, setRefreshing] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);
  const [lastLoadedGrade, setLastLoadedGrade] = useState<GradeLevel | null>(null);
  const loadingRef = React.useRef(false);
  const isInteractingWithGraph = useRef(false);
  const hasInitializedGradeRef = useRef(false);
  const userHasManuallySelectedGradeRef = useRef(false); // Track if user manually selected a grade
  const [error, setError] = useState<string | null>(null);

  // Listen for credential updates
  useEffect(() => {
    const credentialsListener = DeviceEventEmitter.addListener('credentialsAdded', async () => {
      // Auto-refresh when credentials are verified
      setError(null);
      setIsInitialized(false);
      userHasManuallySelectedGradeRef.current = false; // Reset manual selection flag
      hasInitializedGradeRef.current = false; // Reset initialization flag
      // Small delay to ensure AsyncStorage writes have completed
      setTimeout(async () => {
        try {
          await refreshCourses(true);
        } catch (error) {
          console.error('Error refreshing after credentials update:', error);
          setError('Unable to load GPA data. Please try again.');
        }
      }, 100);
    });

    return () => {
      credentialsListener.remove();
    };
  }, [refreshCourses]);
  
  // Update selectedGrade when currentGradeLevel changes, but only on initial load
  useEffect(() => {
    console.log('🔄 useEffect for grade sync - currentGradeLevel changed:', {
      currentGradeLevel,
      selectedGrade,
      hasInitializedGradeRef: hasInitializedGradeRef.current,
      userHasManuallySelectedGrade: userHasManuallySelectedGradeRef.current,
      gradeLevelLoading
    });
    
    // Only auto-update selectedGrade if user hasn't manually selected a grade
    // and the grade level data has finished loading
    if (!userHasManuallySelectedGradeRef.current && !gradeLevelLoading && currentGradeLevel !== selectedGrade) {
      console.log('🔄 Auto-updating selectedGrade to match currentGradeLevel:', currentGradeLevel);
      setSelectedGrade(currentGradeLevel);
      hasInitializedGradeRef.current = true;
    }
  }, [currentGradeLevel, selectedGrade, gradeLevelLoading]);
  
  const allLabels = useMemo(() => ['PR1','PR2','RC1','PR3','PR4','RC2','PR5','PR6','RC3','PR7','PR8','RC4'], []);

  // Memoize valid labels calculation
  const validLabels = useMemo(() => {
    return allLabels.filter(label => {
      const gpaValue = gpaData[label];
      return gpaValue !== undefined && gpaValue.weighted > 0;
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
      // Clear the shared cache to ensure fresh data
      await clearCache();
      // Clear GPA-specific cache as well
      await UnifiedGPAManager.clearGPACache();
      // Refresh courses data with force=true
      await refreshCourses(true);
      // After refresh, recalculate GPA data
      if (coursesData && coursesData.length > 0) {
        const gradeNumber = GRADE_MAP[selectedGrade] || null;
        let filteredCourses = coursesData;
        if (gradeNumber) {
          filteredCourses = coursesData.filter(c => c.gradeYear === gradeNumber);
        }
        const newGpaData = UnifiedGPAManager.calculateCurrentGradeGPA(filteredCourses);
        console.log('🔄 Setting gpaData in handleRefresh:', {
          selectedGrade,
          filteredCoursesCount: filteredCourses.length,
          newGpaDataKeys: Object.keys(newGpaData),
          newGpaDataCount: Object.keys(newGpaData).length
        });
        setGpaData(newGpaData);
      }
    } catch (error) {
      console.error('❌ Error during refresh:', error);
      setError('Unable to refresh GPA data. Please check your connection and try again.');
    } finally {
      setRefreshing(false);
      isInteractingWithGraph.current = wasInteracting;
    }
  };

  // Initial load when component mounts (only once)
  useEffect(() => {
    let isMounted = true;
    const initializeData = async () => {
      if (isInitialized) return;
      if (!isMounted) return;
      
      // Wait for grade level to finish loading before initializing GPA data
      if (gradeLevelLoading) {
        console.log('⏳ Waiting for grade level to load before initializing GPA data...');
        return;
      }

      try {
        setError(null);

        // If coursesData is already loaded in context, use it
        if (coursesData && coursesData.length > 0) {
          const gradeNumber = GRADE_MAP[selectedGrade] || null;
          let initialCourses = coursesData;
          if (gradeNumber) {
            initialCourses = coursesData.filter(c => c.gradeYear === gradeNumber);
          }
          const initialGpaData = UnifiedGPAManager.calculateCurrentGradeGPA(initialCourses);
          console.log('🚀 Initial gpaData setup:', {
            selectedGrade,
            initialCoursesCount: initialCourses.length,
            initialGpaDataKeys: Object.keys(initialGpaData),
            initialGpaDataCount: Object.keys(initialGpaData).length
          });
          setGpaData(initialGpaData);
          setIsInitialized(true);
          return;
        }

        // Otherwise, check credentials and fetch from API
        const result = await SkywardAuth.hasCredentials();
        if (!isMounted) return;
        setHasCredentials(result);
        
        if (result) {
          const gpaResult = await UnifiedGPAManager.getGPAData('All Time', false);
          if (gpaResult.success && gpaResult.rawCourses) {
            let initialCourses = gpaResult.rawCourses;
            const gradeNumber = GRADE_MAP[selectedGrade] || null;
            if (gradeNumber) {
              initialCourses = gpaResult.rawCourses.filter(c => c.gradeYear === gradeNumber);
            }
            const fallbackGpaData = UnifiedGPAManager.calculateCurrentGradeGPA(initialCourses);
            console.log('💾 Fallback gpaData setup:', {
              selectedGrade,
              fallbackCoursesCount: initialCourses.length,
              fallbackGpaDataKeys: Object.keys(fallbackGpaData),
              fallbackGpaDataCount: Object.keys(fallbackGpaData).length
            });
            setGpaData(fallbackGpaData);
          } else {
            throw new Error('Failed to load GPA data');
          }
          if (isMounted) {
            setIsInitialized(true);
          }
        }
      } catch (error) {
        console.error('Error initializing GPA data:', error);
        if (isMounted) {
          setError('Unable to load GPA data. Please check your connection and try again.');
        }
      }
    };
    initializeData();
    return () => {
      isMounted = false;
    };
  }, [coursesData, isInitialized, gradeLevelLoading]);

  // Recalculate GPA data when selectedGrade changes (after initialization)
  useEffect(() => {
    if (!isInitialized || !coursesData || coursesData.length === 0 || gradeLevelLoading) {
      return;
    }

    const gradeNumber = GRADE_MAP[selectedGrade] || null;
    let filteredCourses = coursesData;
    if (gradeNumber) {
      filteredCourses = coursesData.filter(c => c.gradeYear === gradeNumber);
    }
    const newGpaData = UnifiedGPAManager.calculateCurrentGradeGPA(filteredCourses);
    console.log('🔄 Recalculating GPA data for grade change:', {
      selectedGrade,
      filteredCoursesCount: filteredCourses.length,
      newGpaDataKeys: Object.keys(newGpaData),
      newGpaDataCount: Object.keys(newGpaData).length
    });
    setGpaData(newGpaData);
  }, [selectedGrade, isInitialized, coursesData, gradeLevelLoading]);

  // Handle grade selection changes
  const handleGradeChange = useCallback((newGrade: GradeLevel) => {
    console.log('👆 Grade selection changed:', {
      from: selectedGrade,
      to: newGrade
    });
    userHasManuallySelectedGradeRef.current = true; // Mark that user manually selected
    setSelectedGrade(newGrade);
    setActivePointIndex(null);
    setHoverX(null);
    if (coursesData) {
      const gradeNumber = GRADE_MAP[newGrade] || null;
      let filteredCourses = coursesData;
      if (gradeNumber) {
        filteredCourses = coursesData.filter(c => c.gradeYear === gradeNumber);
      }
      const newGpaData = UnifiedGPAManager.calculateCurrentGradeGPA(filteredCourses);
      console.log('📊 Grade change gpaData update:', {
        newGrade,
        filteredCoursesCount: filteredCourses.length,
        newGpaDataKeys: Object.keys(newGpaData),
        newGpaDataCount: Object.keys(newGpaData).length
      });
      setGpaData(newGpaData);
    }
  }, [coursesData]);

  const renderGPAGraph = useCallback(() => {
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
                {`${validLabels[safeIndex]}: ${gpaPoints[safeIndex] === 0 ? '--' : gpaPoints[safeIndex].toFixed(2)}`}
              </Text>
            </View>
          );
        })()}
      </View>
    );
  }, [validLabels, gpaData, hoverX, activePointIndex, isGraphAnimating, colorScheme]);


  const renderGPADisplay = (showPrs : Boolean) => {
    console.log('📊 renderGPADisplay called with showPrs:', showPrs);
    
    // Function to determine if we should show specific PR pairs
    const shouldShowPRPair = (prPair: string[]) => {
      // Check if we have data for the PR pair
      const hasPRData = prPair.every(pr => gpaData[pr]);
      
      if (!hasPRData) return false; // Don't show if we don't have PR data
      
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
      const hasNextPeriodData = nextPeriods.some(period => gpaData[period]);
      
      console.log(`🔍 shouldShowPRPair for [${prPair.join(', ')}]:`, {
        hasPRData,
        nextPeriods,
        hasNextPeriodData,
        shouldShow: !hasNextPeriodData
      });
      
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
                  {`${validLabels[activePointIndex]}: ${gpaPoints[activePointIndex] === 0 ? '--' : gpaPoints[activePointIndex].toFixed(2)}`}
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
                  // console.log(prList.length);
                  // console.log(prList)
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
                      console.log(rcLabels);
                    rows.push(
                      <View className="flex-row justify-between mb-3" key={`${rcLabels[0]}-${rcLabels[1]}`}>
                        <GpaCard label={rcLabels[0]} data={getLabelData(rcLabels[0])} />
                        <GpaCard label={rcLabels[1]} data={getLabelData(rcLabels[1])} />
                      </View>
                    );
                    handledRCs.add(rcLabels[idx]);
                    console.log(getLabelData(prList[0]));
                    console.log(getLabelData(prList[1]));
                    console.log('Legacy showPrs:', showPrs);
                    
                    // Use the new logic for this specific PR pair
                    const shouldShowThisPRPair = shouldShowPRPair(prList);
                    console.log('Should show this PR pair:', shouldShowThisPRPair);
                    
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

            const sm1 = exists('SM1') ? getLabelData('SM1') : fallback;
            const sm2 = exists('SM2') ? getLabelData('SM2') : fallback;
            // Only calculate average if at least one semester has data
            const validSemesters = [sm1, sm2].filter(sem => sem.weighted > 0);
            let finUnweighted, finWeighted;
            
            if (validSemesters.length === 0) {
              finUnweighted = 0;
              finWeighted = 0;
            } else if (validSemesters.length === 1) {
              finUnweighted = validSemesters[0].unweighted;
              finWeighted = validSemesters[0].weighted;
            } else {
              finUnweighted = (sm1.unweighted + sm2.unweighted) / 2;
              finWeighted = (sm1.weighted + sm2.weighted) / 2;
            }

            if (exists('SM1') && exists('SM2')) {
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
            }
            if (!showPrs) {
              rows.push(
                <ManualGradeEntryCard
                  key={`MANCARD-${selectedGrade}`}
                 selectedGrade={selectedGrade} minimized={!!(Object.keys(gpaData).length > 0 || (savedClasses && savedClasses.length > 0))} rawCourses={coursesData} />
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
  if (error) {
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
              } catch (error) {
                setError('Unable to load GPA data. Please try again.');
              }
            }}
            title="Couldn't load GPA data"
          />
        </View>
      </View>
    );
  }

  // Show login prompt if credentials are not set
  if (!hasCredentials && !loading && !isInitialized) {
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

    // console.log(!(Object.keys(gpaData).length > 0 || (savedClasses && savedClasses.length > 0)));

    // console.log("AA" + (Object.keys(gpaData).length > 0));

    // console.log("BB" + !(savedClasses && savedClasses.length > 0));

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
            grades={availableGradeLevels}
            selectedGrade={selectedGrade}
            onSelectGrade={handleGradeChange}
          />
        )}
      </View>

      <View className="flex-1 bg-primary">
        {loading ? (
          <View className="flex-1 justify-center items-center">
            <Text className="text-main text-lg">Loading academic history...</Text>
          </View>
        ) : (selectedGrade === 'All Time' || selectedGrade === currentGradeLevel || (Object.keys(gpaData).length > 0 || (savedClasses && savedClasses.length > 0))) ? (
          (() => {
            const hasGpaData = Object.keys(gpaData).length > 0;
            const hasSavedClasses = !!(savedClasses && savedClasses.length > 0);
            const showPrsValue = !(hasGpaData || hasSavedClasses);
            
            console.log('🔍 showPrs Debug Info:');
            console.log('  - gpaData keys count:', Object.keys(gpaData).length);
            console.log('  - gpaData keys:', Object.keys(gpaData));
            console.log('  - hasGpaData:', hasGpaData);
            console.log('  - savedClasses:', savedClasses);
            console.log('  - savedClasses length:', savedClasses?.length || 0);
            console.log('  - hasSavedClasses:', hasSavedClasses);
            console.log('  - showPrs calculated value:', showPrsValue);
            console.log('  - selectedGrade:', selectedGrade);
            console.log('  - currentGradeLevel:', currentGradeLevel);
            
            return renderGPADisplay(showPrsValue);
          })()
        ) : (
          <ManualGradeEntryCard
            key={`MANCARD-${selectedGrade}`}
            selectedGrade={selectedGrade}
            minimized={!!(Object.keys(gpaData).length > 0 || (savedClasses && savedClasses.length > 0))}
            rawCourses={coursesData}
          />
        )}
      </View>
    </View>
  );
}

export default React.memo(GPA);
