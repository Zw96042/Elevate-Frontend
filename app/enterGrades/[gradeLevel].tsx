import { Stack, useLocalSearchParams } from 'expo-router';
import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, ActivityIndicator, RefreshControl } from 'react-native';
import { useColorScheme } from 'nativewind';
import { colors } from '@/utils/colorTheme';
import { ScrollView } from 'react-native-gesture-handler';
import ClassCard2Sem from '@/components/ClassCard2Sem';
import { UnifiedDataManager, UnifiedCourseData } from '@/lib/unifiedDataManager';
import { UnifiedGPAManager } from '@/lib/unifiedGpaManager';
import { ensureUniqueCourseIds } from '@/utils/uniqueId';

interface CourseData {
  terms: string;
  finalGrade: string;
  sm1: string;
  sm2: string;
  pr1: string;
  pr2: string;
  pr3: string;
  pr4: string;
  pr5: string;
  pr6: string;
  pr7: string;
  pr8: string;
  rc1: string;
  rc2: string;
  rc3: string;
  rc4: string;
  ex1: string;
  ex2: string;
}

interface YearData {
  grade: number;
  courses: Record<string, CourseData>;
}

interface AcademicHistoryData {
  [year: string]: YearData;
  alt?: any;
}

const getGradeLevelName = (gradeNumber: number): string => {
  switch (gradeNumber) {
    case 9: return 'Freshman';
    case 10: return 'Sophomore';
    case 11: return 'Junior';
    case 12: return 'Senior';
    default: return `Grade ${gradeNumber}`;
  }
};

// Helper function to get course level
// Helper to get current grade level from academic data
function getCurrentGradeLevelFromData(academicData: AcademicHistoryData): number {
  const yearKeys = Object.keys(academicData).filter(k => k !== 'alt');
  if (yearKeys.length === 0) return 12; // fallback
  const latestYear = yearKeys.sort().reverse()[0];
  return academicData[latestYear]?.grade ?? 12;
}
const getCourseLevel = (className: string): "AP" | "Honors" | "Regular" => {
  if (!className || typeof className !== 'string' || className.trim() === '') {
    return "Regular";
  }
  
  const normalized = className.toLowerCase().trim();
  
  // Roman numeral normalization
  const normalizeNumbers = (text: string): string => {
    const romanToNumber: { [key: string]: string } = {
      ' i': ' 1', ' ii': ' 2', ' iii': ' 3', ' iv': ' 4', ' v': ' 5', ' vi': ' 6'
    };
    const numberToRoman: { [key: string]: string } = {
      ' 1': ' i', ' 2': ' ii', ' 3': ' iii', ' 4': ' iv', ' 5': ' v', ' 6': ' vi'
    };
    
    let normalizedText = text;
    Object.entries(romanToNumber).forEach(([roman, number]) => {
      normalizedText = normalizedText.replace(new RegExp(roman, 'gi'), number);
    });
    Object.entries(numberToRoman).forEach(([number, roman]) => {
      normalizedText = normalizedText.replace(new RegExp(number, 'gi'), roman);
    });
    return normalizedText;
  };
  
  const apExceptions = ["multivariable calculus", "linear algebra", "stats 2: beyond ap statistics", "computer science 2", "computer science ii", "computer science 3", "computer science iii", "organic chemistry", "art historical methods"];
  const honorsExceptions = ["editorial leadership", "anatomy & physiology", "mentorship", "health science clinical", "robotics 2", "robotics ii", "robotics 3", "robotics iii", "swift coding", "business incubator", "engineering"];
  
  // First check for explicit AP pattern
  const hasAPKeyword = /\bap\b/.test(normalized);
  
  // Check AP exceptions with improved matching
  const isAPException = apExceptions.some(ex => {
    const normalizedCourse = normalizeNumbers(normalized);
    const normalizedEx = normalizeNumbers(ex);
    
    if (normalized === ex || normalizedCourse === normalizedEx) return true;
    if (ex.length > 10 && (normalized.includes(ex) || normalizedCourse.includes(normalizedEx))) return true;
    
    if (ex.length <= 10 && normalized.length > 5) {
      const courseWords = normalizedCourse.split(/\s+/);
      const exWords = normalizedEx.split(/\s+/);
      
      if (courseWords.length >= 2 && exWords.length >= 2) {
        const courseBase = courseWords.slice(0, -1).join(' ');
        const courseLevel = courseWords[courseWords.length - 1];
        const exBase = exWords.slice(0, -1).join(' ');
        const exLevel = exWords[exWords.length - 1];
        
        if (courseBase === exBase && courseLevel === exLevel) return true;
      } else {
        if (ex.includes(normalized) || normalizedEx.includes(normalizedCourse)) return true;
      }
    }
    
    return false;
  });
  
  if (hasAPKeyword || isAPException) return "AP";
  
  // Check for Honors pattern
  const hasHonorsKeyword = /\bhonors?\b/.test(normalized);
  
  // Check Honors exceptions with improved matching
  const isHonorsException = honorsExceptions.some(ex => {
    const normalizedCourse = normalizeNumbers(normalized);
    const normalizedEx = normalizeNumbers(ex);
    
    if (normalized === ex || normalizedCourse === normalizedEx) return true;
    if (ex.length > 10 && (normalized.includes(ex) || normalizedCourse.includes(normalizedEx))) return true;
    
    if (ex.length <= 10 && normalized.length > 5) {
      const courseWords = normalizedCourse.split(/\s+/);
      const exWords = normalizedEx.split(/\s+/);
      
      if (courseWords.length >= 2 && exWords.length >= 2) {
        const courseBase = courseWords[0];
        const courseLevel = courseWords[1];
        const exBase = exWords[0];
        const exLevel = exWords[1];
        
        if (courseBase === exBase && courseLevel === exLevel) return true;
      } else {
        if (ex.includes(normalized) || normalizedEx.includes(normalizedCourse)) return true;
      }
    }
    
    return false;
  });
  
  if (hasHonorsKeyword || isHonorsException) return "Honors";
  
  return "Regular";
};

const AcademicHistoryView = () => {
  const { gradeLevel, preloadedClasses, unifiedCourses: unifiedCoursesParam } = useLocalSearchParams();
  const { colorScheme } = useColorScheme();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [academicData, setAcademicData] = useState<AcademicHistoryData | null>(null);
  const [unifiedCourses, setUnifiedCourses] = useState<UnifiedCourseData[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Get grade level number from route parameter
  const gradeNumber = React.useMemo(() => {
    const gradeMap: Record<string, number> = {
      'Freshman': 9,
      'Sophomore': 10,
      'Junior': 11,
      'Senior': 12
    };
    return gradeMap[gradeLevel.toString()] || 9;
  }, [gradeLevel]);

  // Parse preloaded classes if they exist
  const preloadedCourses = React.useMemo(() => {
    if (preloadedClasses && typeof preloadedClasses === 'string') {
      try {
        const parsed = JSON.parse(preloadedClasses);
        return parsed;
      } catch (error) {
        console.error('Failed to parse preloaded classes:', error);
      }
    }
    return null;
  }, [preloadedClasses]);

  // Parse unified courses if they exist
  const passedUnifiedCourses = React.useMemo(() => {
    if (unifiedCoursesParam && typeof unifiedCoursesParam === 'string') {
      try {
        const parsed = JSON.parse(unifiedCoursesParam);
        // console.log('📊 Parsed unified courses from params:', parsed.length, 'courses');
        return parsed;
      } catch (error) {
        console.error('Failed to parse unified courses:', error);
      }
    }
    return null;
  }, [preloadedClasses]);

  const loadData = useCallback(async (forceRefresh = false) => {
    try {
      console.log(`📱 [GradeLevel ${gradeLevel}] loadData called with forceRefresh:`, forceRefresh);
      console.log(`📚 Grade number: ${gradeNumber}`);
      
      setError(null);
      if (forceRefresh) setRefreshing(true);
      else setLoading(true);

      // First get unified data to determine current grade level
      console.log('🔄 Fetching unified data to determine current grade...');
      const unifiedResult = await UnifiedDataManager.getCombinedData(forceRefresh);
      console.log('📊 Unified result:', {
        success: unifiedResult.success,
        coursesCount: unifiedResult.courses?.length || 0,
        error: unifiedResult.error,
        lastUpdated: unifiedResult.lastUpdated
      });
      
      let currentGrade = 12; // Default
      
      if (unifiedResult.success && unifiedResult.courses) {
  // Convert to academic format to determine grade level
  console.log('🔄 Converting to academic format...');
  // Use the raw object format for academic history
  const academicFormat = unifiedResult.courses;
  // If academicFormat is an array, you may need to convert it to object format if needed
  // For now, fallback to default logic
  // If you have the raw object, use getCurrentGradeLevelFromData
  // currentGrade = getCurrentGradeLevelFromData(academicFormat); // Uncomment if you have object
  // Otherwise, keep as default
  console.log('🎯 Current grade level detected:', currentGrade);
      }
      
      const isCurrent = gradeNumber === currentGrade;
      console.log(`🔍 Is current grade level? ${isCurrent} (page: ${gradeNumber}, current: ${currentGrade})`);

      if (isCurrent) {
        console.log('✅ Using current grade level path - unified data');
        // Use unified data for current grade level (combines scrape report + academic history)
        if (unifiedResult.success && unifiedResult.courses) {
          console.log('📝 Setting unified courses:', unifiedResult.courses.length);
          setUnifiedCourses(unifiedResult.courses);
          setAcademicData(null); // Only set academicData with object format
          if (unifiedResult.error) {
            setError(`Note: ${unifiedResult.error}`);
          }
        } else {
          console.log('⚠️ Unified data failed, falling back to GPA manager...');
          // Fallback to GPA manager for academic history only
          const gpaResult = await UnifiedGPAManager.getGPAData('All Time', forceRefresh);
          console.log('📊 GPA fallback result:', { success: gpaResult.success, error: gpaResult.error });
          
          if (gpaResult.success && gpaResult.rawCourses) {
            // Only set academicData if rawCourses is an object (not array)
            if (typeof gpaResult.rawCourses === 'object' && !Array.isArray(gpaResult.rawCourses)) {
              setAcademicData(gpaResult.rawCourses);
              setUnifiedCourses(null);
            } else {
              setUnifiedCourses(gpaResult.rawCourses);
              setAcademicData(null);
            }
            setError(`Using academic history fallback: ${unifiedResult.error}`);
          } else {
            setError(`Failed to load any data: ${unifiedResult.error || gpaResult.error}`);
          }
        }
      } else {
        console.log('📚 Using historical grade level path - academic data only');
        // Use GPA manager for past grade levels (academic history only)
        const gradeLevel = getGradeLevelName(gradeNumber) as 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';
        console.log('🔄 Fetching GPA data for grade level:', gradeLevel);
        
        const gpaResult = await UnifiedGPAManager.getGPAData(gradeLevel, forceRefresh);
        console.log('📊 Historical GPA result:', { 
          success: gpaResult.success, 
          rawCoursesCount: gpaResult.rawCourses?.length || 0,
          error: gpaResult.error 
        });
        
        if (gpaResult.success && gpaResult.rawCourses) {
          // Only set academicData if rawCourses is an object (not array)
          if (typeof gpaResult.rawCourses === 'object' && !Array.isArray(gpaResult.rawCourses)) {
            console.log('📚 Academic format for historical data:', Object.keys(gpaResult.rawCourses));
            setAcademicData(gpaResult.rawCourses);
            setUnifiedCourses(null); // Clear unified data when using academic history
          } else {
            setUnifiedCourses(gpaResult.rawCourses);
            setAcademicData(null);
          }
          if (gpaResult.error) {
            setError(`Note: ${gpaResult.error}`);
          }
        } else {
          console.log('❌ Failed to load historical data');
          setError(gpaResult.error || 'Failed to load historical data');
          setAcademicData(null);
          setUnifiedCourses(null);
        }
      }
    } catch (error) {
      console.error('❌ Failed to load data in [gradeLevel].tsx:', error);
      setError(error instanceof Error ? error.message : 'Failed to load data');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [gradeNumber]);

  useEffect(() => {
    // Priority 1: If we have passed unified courses data from GPA page, use it directly
    if (passedUnifiedCourses && passedUnifiedCourses.length > 0) {
      // console.log('🎯 Using passed unified courses data:', passedUnifiedCourses.length, 'courses');
      setUnifiedCourses(passedUnifiedCourses);
      setAcademicData(null); // Clear academic data when using unified
      setLoading(false);
      return;
    }

    // Priority 2: If we have preloaded classes, use them and don't load from API
    if (preloadedCourses && preloadedCourses.length > 0) {
      console.log('💾 Using preloaded courses data:', preloadedCourses.length, 'courses');
      setLoading(false);
      return;
    }
    
    // Priority 3: Load data from API
    console.log('🔄 Loading data from API...');
    loadData();
  }, [loadData, preloadedCourses, passedUnifiedCourses]);

  const onRefresh = useCallback(() => {
    loadData(true);
  }, [loadData]);

  // Determine if this is the current grade level
  const isCurrent = React.useMemo(() => {
    // You are currently in 10th grade
    return gradeNumber === 10;
  }, [gradeNumber]);

  // Filter courses for the specific grade level
  const gradeData = React.useMemo(() => {
    // If we have unified courses data, create a synthetic gradeData structure
    if (unifiedCourses && unifiedCourses.length > 0) {
      // console.log('📊 Creating synthetic gradeData from unified courses');
      const coursesRecord: Record<string, CourseData> = {};
      
      unifiedCourses.forEach(course => {
        const bucketNames = course.currentScores?.map(s => s.bucket) || [];
        // console.log('🔍 DEEP ANALYSIS OF COURSE:', course.courseName, {
        //   fullCourse: JSON.stringify(course, null, 2),
        //   possibleBuckets: bucketNames
        // });
        
        // For current grade, use the numerical percentage scores for display (as strings)
        if (isCurrent && course.currentScores && Array.isArray(course.currentScores) && course.currentScores.length > 0) {
          // Get current scores by bucket (numerical)
          const getScoreByBucket = (bucket: string): string => {
            const scoreObj = course.currentScores?.find(s => s.bucket === bucket);
            return scoreObj && typeof scoreObj.score === 'number' ? String(scoreObj.score) : '';
          };

          // console.log('🔄 Using currentScores as numerical grades for:', course.courseName, {
          //   currentScoresLength: course.currentScores.length,
          //   currentScores: course.currentScores,
          //   sample: course.currentScores[0],
          //   sm1: getScoreByBucket('S1'),
          //   sm2: getScoreByBucket('S2'),
          //   rc1: getScoreByBucket('TERM 3'),
          //   rc2: getScoreByBucket('TERM 6'),
          //   rc3: getScoreByBucket('TERM 9'),
          //   rc4: getScoreByBucket('TERM 12'),
          // });

          coursesRecord[course.courseName] = {
            terms: course.termLength || 'unknown',
            finalGrade: '', // Current courses don't have final grades yet
            sm1: getScoreByBucket('S1'),
            sm2: getScoreByBucket('S2'),
            pr1: '',
            pr2: '',
            pr3: '',
            pr4: '',
            pr5: '',
            pr6: '',
            pr7: '',
            pr8: '',
            rc1: getScoreByBucket('TERM 3'),
            rc2: getScoreByBucket('TERM 6'),
            rc3: getScoreByBucket('TERM 9'),
            rc4: getScoreByBucket('TERM 12'),
            ex1: '',
            ex2: ''
          };
        } else {
          // For historical grades or when currentScores is not an array, use the historical data
          console.log('🔄 Using historical grades for:', course.courseName, {
            hasCurrentScores: !!course.currentScores,
            currentScoresType: typeof course.currentScores,
            currentScoresValue: course.currentScores,
            isArray: Array.isArray(course.currentScores),
            isCurrent
          });
          
          coursesRecord[course.courseName] = {
            terms: course.termLength || 'unknown',
            finalGrade: course.historicalGrades?.finalGrade || '',
            sm1: course.historicalGrades?.sm1 || '',
            sm2: course.historicalGrades?.sm2 || '',
            pr1: course.historicalGrades?.pr1 || '',
            pr2: course.historicalGrades?.pr2 || '',
            pr3: course.historicalGrades?.pr3 || '',
            pr4: course.historicalGrades?.pr4 || '',
            pr5: course.historicalGrades?.pr5 || '',
            pr6: course.historicalGrades?.pr6 || '',
            pr7: course.historicalGrades?.pr7 || '',
            pr8: course.historicalGrades?.pr8 || '',
            rc1: course.historicalGrades?.rc1 || '',
            rc2: course.historicalGrades?.rc2 || '',
            rc3: course.historicalGrades?.rc3 || '',
            rc4: course.historicalGrades?.rc4 || '',
            ex1: '',
            ex2: ''
          };
        }
      });
      
      // console.log('📊 Sample course data created:', Object.keys(coursesRecord).length > 0 ? {
      //   courseName: Object.keys(coursesRecord)[0],
      //   courseData: coursesRecord[Object.keys(coursesRecord)[0]]
      // } : 'No courses');
      
      return {
        grade: gradeNumber,
        courses: coursesRecord
      };
    }
    
    // Otherwise, use academicData as before
    if (!academicData) return null;
    
    // Find the year data that matches our target grade level
    const yearEntry = Object.entries(academicData).find(([year, data]) => {
      return year !== 'alt' && data.grade === gradeNumber;
    });
    
    return yearEntry ? yearEntry[1] : null;
  }, [academicData, gradeNumber, unifiedCourses, isCurrent]);

  const courses = React.useMemo(() => {
    let coursesArray: Array<{
      courseName: string;
      courseData: CourseData;
      savedLevel: string | null;
    }> = [];
    
    // First priority: Use unified courses data
    if (unifiedCourses && unifiedCourses.length > 0) {
      coursesArray = unifiedCourses
        .filter(course => {
          // For current grade, check current scores; for past grades, check historical grades
          if (isCurrent) {
            const hasCurrentScores = course.currentScores && course.currentScores.length > 0;
            return hasCurrentScores || course.instructor; // Include if has current scores or instructor info
          } else {
            const hasHistoricalGrades = course.historicalGrades.finalGrade !== "P" && (
              course.historicalGrades.sm1 || 
              course.historicalGrades.sm2 || 
              course.historicalGrades.finalGrade ||
              course.historicalGrades.rc1 ||
              course.historicalGrades.rc2 ||
              course.historicalGrades.rc3 ||
              course.historicalGrades.rc4
            );
            return hasHistoricalGrades;
          }
        })
        .sort((a, b) => a.courseName.localeCompare(b.courseName))
        .map(course => {
          // For current grade level, use current scores; for past grades, use historical grades
          if (isCurrent && course.currentScores && course.currentScores.length > 0) {
            // Calculate semester grades from current scores (percentages)
            const s1Score = course.currentScores.find(score => score.bucket === 'S1')?.score || -1;
            const s2Score = course.currentScores.find(score => score.bucket === 'S2')?.score || -1;
            const q1Score = course.currentScores.find(score => score.bucket === 'Q1')?.score || -1;
            const q2Score = course.currentScores.find(score => score.bucket === 'Q2')?.score || -1;
            const q3Score = course.currentScores.find(score => score.bucket === 'Q3')?.score || -1;
            const q4Score = course.currentScores.find(score => score.bucket === 'Q4')?.score || -1;

            // Convert scores to letter grades for storage
            const scoreToLetterGrade = (score: number): string => {
              if (score === -1) return '';
              if (score >= 90) return 'A';
              if (score >= 80) return 'B';
              if (score >= 70) return 'C';
              if (score >= 60) return 'D';
              return 'F';
            };

            return {
              courseName: course.courseName,
              courseData: {
                terms: course.termLength || 'unknown',
                finalGrade: '',
                sm1: scoreToLetterGrade(s1Score),
                sm2: scoreToLetterGrade(s2Score),
                pr1: scoreToLetterGrade(q1Score),
                pr2: scoreToLetterGrade(q2Score),
                pr3: scoreToLetterGrade(q3Score),
                pr4: scoreToLetterGrade(q4Score),
                pr5: '',
                pr6: '',
                pr7: '',
                pr8: '',
                rc1: '',
                rc2: '',
                rc3: '',
                rc4: '',
                ex1: '',
                ex2: ''
              },
              savedLevel: null
            };
          } else {
            // Use historical grades for past grade levels
            return {
              courseName: course.courseName,
              courseData: {
                terms: course.termLength || 'unknown',
                finalGrade: course.historicalGrades.finalGrade || '',
                sm1: course.historicalGrades.sm1 || '',
                sm2: course.historicalGrades.sm2 || '',
                pr1: course.historicalGrades.pr1 || '',
                pr2: course.historicalGrades.pr2 || '',
                pr3: course.historicalGrades.pr3 || '',
                pr4: course.historicalGrades.pr4 || '',
                pr5: course.historicalGrades.pr5 || '',
                pr6: course.historicalGrades.pr6 || '',
                pr7: course.historicalGrades.pr7 || '',
                pr8: course.historicalGrades.pr8 || '',
                rc1: course.historicalGrades.rc1 || '',
                rc2: course.historicalGrades.rc2 || '',
                rc3: course.historicalGrades.rc3 || '',
                rc4: course.historicalGrades.rc4 || '',
                ex1: '',
                ex2: ''
              },
              savedLevel: null
            };
          }
        });
    }
    // Second priority: Use academic history data for past grade levels
    else if (gradeData) {
      coursesArray = Object.entries(gradeData.courses)
        .filter(([courseName, courseData]) => {
          // Filter out courses with no meaningful data
          return courseData.finalGrade !== "P" && (
            courseData.sm1 || 
            courseData.sm2 || 
            courseData.finalGrade
          );
        })
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([courseName, courseData]) => ({
          courseName,
          courseData,
          savedLevel: null // No saved level for API data
        }));
    } 
    // Last priority: Use preloaded classes from AsyncStorage
    else if (preloadedCourses && Array.isArray(preloadedCourses)) {
      // Convert from our saved format to the expected format
      coursesArray = preloadedCourses.map(course => ({
        courseName: course.name,
        courseData: {
          terms: course.terms,
          finalGrade: course.grades.finalGrade,
          sm1: course.grades.sm1,
          sm2: course.grades.sm2,
          pr1: course.grades.pr1,
          pr2: course.grades.pr2,
          pr3: course.grades.pr3,
          pr4: course.grades.pr4,
          pr5: course.grades.pr5,
          pr6: course.grades.pr6,
          pr7: course.grades.pr7,
          pr8: course.grades.pr8,
          rc1: course.grades.rc1,
          rc2: course.grades.rc2,
          rc3: course.grades.rc3,
          rc4: course.grades.rc4,
          ex1: course.grades.ex1 || '',
          ex2: course.grades.ex2 || ''
        },
        savedLevel: course.level // Use saved level from AsyncStorage
      })).sort((a, b) => a.courseName.localeCompare(b.courseName));
    }
    
    // Ensure all courses have unique IDs
    return ensureUniqueCourseIds(coursesArray, gradeLevel.toString());
  }, [unifiedCourses, gradeData, preloadedCourses, gradeLevel]);

  // console.log("GRADE DATA: ", gradeData);
  // console.log("UNIFIED COURSES: ", unifiedCourses?.length || 0, "courses");
  // console.log("ACADEMIC DATA: ", academicData ? Object.keys(academicData) : "null");

  if (loading && !refreshing) {
    return (
      <>
        <Stack.Screen
          options={{
            title: `${getGradeLevelName(gradeNumber)} Academic History`,
            headerStyle: { backgroundColor: '#2563eb' },
            headerTintColor: '#fff',
            headerTitleStyle: {
              fontWeight: 'bold',
              fontSize: 18,
            },
            headerBackTitle: 'GPA',
          }}
        />
        <View className="flex-1 bg-primary items-center justify-center">
          <ActivityIndicator size="large" color="#2563eb" />
          <Text className="text-accent mt-4">Loading academic history...</Text>
        </View>
      </>
    );
  }

  if (error) {
    return (
      <>
        <Stack.Screen
          options={{
            title: `${getGradeLevelName(gradeNumber)} Academic History`,
            headerStyle: { backgroundColor: '#2563eb' },
            headerTintColor: '#fff',
            headerTitleStyle: {
              fontWeight: 'bold',
              fontSize: 18,
            },
            headerBackTitle: 'GPA',
          }}
        />
        <ScrollView 
          className="flex-1 bg-primary"
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
          }
        >
          <View className="flex-1 items-center justify-center p-6">
            <Text className="text-red-500 text-lg font-semibold mb-2">Error Loading Data</Text>
            <Text className="text-accent text-center">{error}</Text>
          </View>
        </ScrollView>
      </>
    );
  }

  if (courses.length === 0) {
    return (
      <>
        <Stack.Screen
          options={{
            title: `${getGradeLevelName(gradeNumber)} Academic History`,
            headerStyle: { backgroundColor: '#2563eb' },
            headerTintColor: '#fff',
            headerTitleStyle: {
              fontWeight: 'bold',
              fontSize: 18,
            },
            headerBackTitle: 'GPA',
          }}
        />
        <ScrollView 
          className="flex-1 bg-primary"
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
          }
        >
          <View className="mx-6 mt-6">
            <View className="bg-cardColor rounded-2xl p-6 border border-dashed border-accent shadow-md">
              <Text className="text-main text-lg mb-3 text-center">
                No academic history found for {getGradeLevelName(gradeNumber)} year.
              </Text>
              <Text className="text-accent text-center">
                This could mean you haven't completed this grade level yet, or the data hasn't been updated in Skyward.
              </Text>
            </View>
          </View>
        </ScrollView>
      </>
    );
  }

  return (
    <>
      <Stack.Screen
        options={{
          title: `Academic History`,
          headerStyle: { backgroundColor: '#2563eb' },
          headerTintColor: '#fff',
          headerTitleStyle: {
            fontWeight: 'bold',
            fontSize: 18,
          },
          headerBackTitle: 'GPA',
        }}
      />
      <ScrollView 
        className="flex-1 bg-primary"
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
      >
        {/* Header Info */}
        <View className="mx-6 mt-6 mb-4">
          <View className="bg-cardColor rounded-2xl p-4 shadow-sm">
            <Text className="text-main text-xl font-semibold mb-2">
              {getGradeLevelName(gradeNumber)} Year Overview
            </Text>
            <View className="flex-row items-center justify-between">
              <Text className="text-accent">
                Total Courses: {courses.length}
              </Text>
              {!isCurrent && (
                <Text className="text-xs text-accent opacity-75">
                  Historical Data
                </Text>
              )}
              {isCurrent && (
                <Text className="text-xs text-accent opacity-75">
                  Live Current Grades
                </Text>
              )}
            </View>
            
            {/* Debug info for grade source */}
            <Text className="text-xs text-accent opacity-50 mt-2">
              Data source: {
                passedUnifiedCourses ? 'Passed from GPA Page' : 
                unifiedCourses ? 'Current Scores + Historical Structure' : 
                preloadedCourses ? 'Saved Local Data' :
                'Pure Academic History'
              }
            </Text>
          </View>
        </View>
        {/* Course List */}
        

        {/* Course List */}
        {courses.map((course) => {
          const { courseName, courseData, savedLevel } = course;
          // Use saved level if available, otherwise calculate it
          const courseLevel = savedLevel || getCourseLevel(courseName);
          
          // For current grade level, get actual percentage scores from unified data
          let sm1Grade = -1;
          let sm2Grade = -1;
          
          if (isCurrent && unifiedCourses) {
            // Find the unified course to get the actual percentage scores
            const unifiedCourse = unifiedCourses.find(uc => uc.courseName === courseName);
            if (unifiedCourse && unifiedCourse.currentScores) {
              const s1Score = unifiedCourse.currentScores.find(score => score.bucket === 'S1');
              const s2Score = unifiedCourse.currentScores.find(score => score.bucket === 'S2');
              sm1Grade = s1Score?.score !== undefined ? s1Score.score : -1;
              sm2Grade = s2Score?.score !== undefined ? s2Score.score : -1;
            }
          } else {
            // For historical grades, parse the letter grades or percentages
            sm1Grade = courseData.sm1 && courseData.sm1 !== "" && courseData.sm1 !== "P" && courseData.sm1 !== "X" 
              ? Number(courseData.sm1) 
              : -1;
            sm2Grade = courseData.sm2 && courseData.sm2 !== "" && courseData.sm2 !== "P" && courseData.sm2 !== "X" 
              ? Number(courseData.sm2) 
              : -1;
          }

          return (
            <ClassCard2Sem
              key={course.id}
              name={courseName}
              teacher=""
              s1={{ categories: { names: [], weights: [] }, total: sm1Grade }}
              s2={{ categories: { names: [], weights: [] }, total: sm2Grade }}
              term="SM1 Grade"
              gradeLevel={gradeLevel.toString()}
              courseLevel={courseLevel}
              showDeleteAction={false}
              termLabels={{ s1: "Fall", s2: "Spring" }}
            />
          );
        })}

        {/* Bottom spacing */}
        <View className="h-6" />
      </ScrollView>
    </>
  );
};

export default AcademicHistoryView;