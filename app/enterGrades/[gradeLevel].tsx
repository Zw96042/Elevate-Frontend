import { Stack, useLocalSearchParams } from 'expo-router';
import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  ActivityIndicator,
  RefreshControl,
  TextInput,
  TouchableOpacity,
  DeviceEventEmitter,
} from 'react-native';
import { ScrollView } from 'react-native-gesture-handler';
import ClassCard2Sem from '@/components/ClassCard2Sem';
import { DataService, type UnifiedCourseData } from '@/lib';
import { ensureUniqueCourseIds } from '@/utils/uniqueId';
import { logger, Modules } from '@/lib/utils/logger';
import {
  loadManualClasses,
  normalizeManualClass,
  saveManualClass,
  type HistoricalGradeLevel,
  type SavedManualClass,
} from '@/lib/utils/manual-gpa';

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

const getGradeLevelName = (gradeNumber: number): string => {
  switch (gradeNumber) {
    case 9: return 'Freshman';
    case 10: return 'Sophomore';
    case 11: return 'Junior';
    case 12: return 'Senior';
    default: return `Grade ${gradeNumber}`;
  }
};

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
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [unifiedCourses, setUnifiedCourses] = useState<UnifiedCourseData[] | null>(null);
  const [manualClasses, setManualClasses] = useState<SavedManualClass[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [className, setClassName] = useState('');
  const [fallGrade, setFallGrade] = useState('');
  const [springGrade, setSpringGrade] = useState('');
  const [formError, setFormError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const acceptPreloadedRef = React.useRef(true);
  const manualLoadIDRef = React.useRef(0);

  const selectedGradeLevel = React.useMemo<HistoricalGradeLevel>(() => {
    const value = Array.isArray(gradeLevel) ? gradeLevel[0] : gradeLevel;
    return ['Freshman', 'Sophomore', 'Junior', 'Senior'].includes(value ?? '')
      ? value as HistoricalGradeLevel
      : 'Freshman';
  }, [gradeLevel]);

  // Get grade level number from route parameter
  const gradeNumber = React.useMemo(() => {
    const gradeMap: Record<string, number> = {
      'Freshman': 9,
      'Sophomore': 10,
      'Junior': 11,
      'Senior': 12
    };
    return gradeMap[selectedGradeLevel];
  }, [selectedGradeLevel]);

  // Parse preloaded classes if they exist
  const preloadedCourses = React.useMemo(() => {
    if (preloadedClasses && typeof preloadedClasses === 'string') {
      try {
        const parsed: unknown = JSON.parse(preloadedClasses);
        return Array.isArray(parsed)
          ? parsed.flatMap(row => {
              const normalized = normalizeManualClass(row);
              return normalized ? [normalized] : [];
            })
          : [];
      } catch (error) {
        logger.error(Modules.PAGE_GPA, 'Failed to parse preloaded classes', error);
      }
    }
    return [];
  }, [preloadedClasses]);

  // Parse unified courses if they exist
  const passedUnifiedCourses = React.useMemo(() => {
    if (unifiedCoursesParam && typeof unifiedCoursesParam === 'string') {
      try {
        const parsed: unknown = JSON.parse(unifiedCoursesParam);
        return Array.isArray(parsed) ? parsed as UnifiedCourseData[] : null;
      } catch (error) {
        logger.error(Modules.PAGE_GPA, 'Failed to parse unified courses', error);
      }
    }
    return null;
  }, [unifiedCoursesParam]);

  const loadManualData = useCallback(async () => {
    const loadID = ++manualLoadIDRef.current;
    const stored = await loadManualClasses(selectedGradeLevel);
    if (loadID === manualLoadIDRef.current) {
      setManualClasses(stored.length > 0 || !acceptPreloadedRef.current ? stored : preloadedCourses);
    }
  }, [preloadedCourses, selectedGradeLevel]);

  const loadData = useCallback(async (forceRefresh = false) => {
    try {
      setError(null);
      if (forceRefresh) setRefreshing(true);
      else setLoading(true);

      const unifiedResult = await DataService.getCombinedData(forceRefresh);
      if (unifiedResult.success && unifiedResult.courses) {
        setUnifiedCourses(unifiedResult.courses);
      } else {
        setError(unifiedResult.error || 'Failed to load historical data');
        setUnifiedCourses([]);
      }
    } catch (error) {
      logger.error(Modules.PAGE_GPA, 'Failed to load grade-level data', error);
      setError(error instanceof Error ? error.message : 'Failed to load data');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void loadManualData();

    // If the GPA tab passed its current snapshot, use it without another request.
    if (passedUnifiedCourses) {
      setUnifiedCourses(passedUnifiedCourses);
      setLoading(false);
      return;
    }

    // Manual history remains usable offline and without Skyward credentials.
    if (preloadedCourses.length > 0) {
      setUnifiedCourses([]);
      setLoading(false);
      return;
    }

    void loadData();
  }, [loadData, loadManualData, preloadedCourses, passedUnifiedCourses]);

  useEffect(() => {
    const listener = DeviceEventEmitter.addListener('classDeleted', () => {
      void loadManualData();
      DeviceEventEmitter.emit('manualGradesChanged');
    });
    return () => listener.remove();
  }, [loadManualData]);

  useEffect(() => {
    const invalid = DeviceEventEmitter.addListener('credentialsInvalid', () => {
      acceptPreloadedRef.current = false;
      manualLoadIDRef.current += 1;
      setManualClasses([]);
    });
    const added = DeviceEventEmitter.addListener('credentialsAdded', () => {
      // Never fall back to route data captured under the previous account.
      acceptPreloadedRef.current = false;
      void loadManualData();
    });
    return () => {
      invalid.remove();
      added.remove();
    };
  }, [loadManualData]);

  const onRefresh = useCallback(() => {
    void Promise.all([loadData(true), loadManualData()]);
  }, [loadData, loadManualData]);

  const currentGradeNumber = React.useMemo(() => {
    const years = (unifiedCourses ?? [])
      .map(course => course.gradeYear)
      .filter((year): year is number => Number.isInteger(year));
    return years.length > 0 ? Math.max(...years) : null;
  }, [unifiedCourses]);
  const isCurrent = currentGradeNumber === gradeNumber;

  const handleAddClass = useCallback(async () => {
    const parseGrade = (value: string): number | null => {
      if (!value.trim()) return -1;
      const parsed = Number(value);
      return Number.isFinite(parsed) && parsed >= 0 && parsed <= 110 ? parsed : null;
    };
    const sm1 = parseGrade(fallGrade);
    const sm2 = parseGrade(springGrade);
    if (!className.trim()) {
      setFormError('Enter a class name.');
      return;
    }
    if (sm1 === null || sm2 === null) {
      setFormError('Grades must be between 0 and 110.');
      return;
    }
    if (sm1 < 0 && sm2 < 0) {
      setFormError('Enter at least one semester grade.');
      return;
    }

    setSaving(true);
    setFormError(null);
    try {
      const updated = await saveManualClass(selectedGradeLevel, {
        className: className.trim(),
        sm1,
        sm2,
      });
      setManualClasses(updated);
      setClassName('');
      setFallGrade('');
      setSpringGrade('');
      DeviceEventEmitter.emit('manualGradesChanged');
    } catch (saveError) {
      logger.error(Modules.PAGE_GPA, 'Failed to save manual class', saveError);
      setFormError('Could not save this class. Please try again.');
    } finally {
      setSaving(false);
    }
  }, [className, fallGrade, selectedGradeLevel, springGrade]);

  const courses = React.useMemo(() => {
    let coursesArray: {
      courseName: string;
      courseData: CourseData;
      savedLevel: string | null;
      isManual: boolean;
    }[] = [];

    const text = (value: unknown): string => value == null ? '' : String(value);
    if (unifiedCourses && unifiedCourses.length > 0) {
      coursesArray = unifiedCourses
        .filter(course => course.gradeYear === gradeNumber)
        .sort((a, b) => a.courseName.localeCompare(b.courseName))
        .map(course => {
          if (isCurrent && course.currentScores && course.currentScores.length > 0) {
            const score = (bucket: string): string => {
              const value = course.currentScores.find(item => item.bucket === bucket)?.score;
              return typeof value === 'number' && Number.isFinite(value) ? String(value) : '';
            };
            return {
              courseName: course.courseName,
              courseData: {
                terms: course.termLength || 'unknown',
                finalGrade: '',
                sm1: score('S1'), sm2: score('S2'),
                pr1: score('Q1'), pr2: score('Q2'),
                pr3: score('Q3'), pr4: score('Q4'),
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
              savedLevel: null,
              isManual: false,
            };
          } else {
            const history = course.historicalGrades ?? {};
            return {
              courseName: course.courseName,
              courseData: {
                terms: course.termLength || 'unknown',
                finalGrade: text(history.finalGrade),
                sm1: text(history.sm1), sm2: text(history.sm2),
                pr1: text(history.pr1), pr2: text(history.pr2),
                pr3: text(history.pr3), pr4: text(history.pr4),
                pr5: text(history.pr5), pr6: text(history.pr6),
                pr7: text(history.pr7), pr8: text(history.pr8),
                rc1: text(history.rc1), rc2: text(history.rc2),
                rc3: text(history.rc3), rc4: text(history.rc4),
                ex1: text(history.ex1), ex2: text(history.ex2),
              },
              savedLevel: null,
              isManual: false,
            };
          }
        });
    }

    const serverNames = new Set(coursesArray.map(course => course.courseName.trim().toLocaleLowerCase()));
    const manualRows = manualClasses
      .filter(course => !serverNames.has(course.className.trim().toLocaleLowerCase()))
      .map(course => ({
        courseName: course.className,
        courseData: {
          terms: '1 - 4',
          finalGrade: '',
          sm1: course.sm1 >= 0 ? String(course.sm1) : '',
          sm2: course.sm2 >= 0 ? String(course.sm2) : '',
          pr1: '', pr2: '', pr3: '', pr4: '',
          pr5: '', pr6: '', pr7: '', pr8: '',
          rc1: text(course.rc1), rc2: text(course.rc2),
          rc3: text(course.rc3), rc4: text(course.rc4),
          ex1: '', ex2: '',
        },
        savedLevel: course.level ?? null,
        isManual: true,
      }));

    return ensureUniqueCourseIds(
      [...coursesArray, ...manualRows].sort((a, b) => a.courseName.localeCompare(b.courseName)),
      selectedGradeLevel
    );
  }, [gradeNumber, isCurrent, manualClasses, selectedGradeLevel, unifiedCourses]);


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

  if (error && courses.length === 0 && manualClasses.length === 0) {
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
          <View className="bg-cardColor rounded-2xl p-4">
            <Text className="text-main text-xl font-semibold mb-2">
              {getGradeLevelName(gradeNumber)} Year Overview
            </Text>
            <View className="flex-row items-center justify-between">
              <Text className="text-accent">
                Total Courses: {courses.length}
              </Text>
            </View>
          
          </View>
        </View>

        <View className="mx-6 mb-5 rounded-2xl bg-cardColor p-4">
          <Text className="text-main text-lg font-semibold mb-3">Add a class</Text>
          <TextInput
            className="border border-accent rounded-xl px-4 py-3 text-main bg-primary mb-3"
            placeholder="Class name"
            placeholderTextColor="#94a3b8"
            value={className}
            onChangeText={setClassName}
            autoCorrect={false}
          />
          <View className="flex-row gap-3">
            <TextInput
              className="flex-1 border border-accent rounded-xl px-4 py-3 text-main bg-primary"
              placeholder="Fall %"
              placeholderTextColor="#94a3b8"
              value={fallGrade}
              onChangeText={setFallGrade}
              keyboardType="decimal-pad"
            />
            <TextInput
              className="flex-1 border border-accent rounded-xl px-4 py-3 text-main bg-primary"
              placeholder="Spring %"
              placeholderTextColor="#94a3b8"
              value={springGrade}
              onChangeText={setSpringGrade}
              keyboardType="decimal-pad"
            />
          </View>
          {formError && <Text className="text-red-500 mt-2">{formError}</Text>}
          <TouchableOpacity
            className={`rounded-xl py-3 mt-3 ${saving ? 'bg-accent' : 'bg-highlight'}`}
            disabled={saving}
            onPress={() => void handleAddClass()}
          >
            <Text className="text-highlightText text-center font-bold">
              {saving ? 'Saving…' : 'Add Class'}
            </Text>
          </TouchableOpacity>
        </View>

        {courses.length === 0 && (
          <View className="mx-6 mb-5 bg-cardColor rounded-2xl p-6 border border-dashed border-accent">
            <Text className="text-main text-lg mb-2 text-center">
              No classes yet for {selectedGradeLevel} year.
            </Text>
            <Text className="text-accent text-center">
              Add your semester grades above. They stay available offline on this account.
            </Text>
          </View>
        )}

        {courses.map((course) => {
          const { courseName, courseData, savedLevel, isManual } = course;
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
              sm1Grade = typeof s1Score?.score === 'number' && Number.isFinite(s1Score.score)
                ? s1Score.score : -1;
              sm2Grade = typeof s2Score?.score === 'number' && Number.isFinite(s2Score.score)
                ? s2Score.score : -1;
            }
          } else {
            // For historical grades, parse the letter grades or percentages
            const parsedSM1 = Number(courseData.sm1);
            const parsedSM2 = Number(courseData.sm2);
            sm1Grade = courseData.sm1 !== '' && Number.isFinite(parsedSM1) ? parsedSM1 : -1;
            sm2Grade = courseData.sm2 !== '' && Number.isFinite(parsedSM2) ? parsedSM2 : -1;
          }

          return (
            <ClassCard2Sem
              key={course.id}
              name={courseName}
              teacher=""
              s1={{ categories: { names: [], weights: [] }, total: sm1Grade }}
              s2={{ categories: { names: [], weights: [] }, total: sm2Grade }}
              term="SM1 Grade"
              gradeLevel={selectedGradeLevel}
              courseLevel={courseLevel}
              showDeleteAction={isManual}
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
