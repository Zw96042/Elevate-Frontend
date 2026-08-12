import React, { useCallback, useEffect, useState } from 'react';
import { DeviceEventEmitter, Text, TouchableOpacity, View } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { getAccountScopedItem } from '@/lib/utils/account-scoped-storage';

const ManualGradeEntryCard = ({ selectedGrade, minimized = false, rawCourses = null }: { selectedGrade: string; minimized?: boolean; rawCourses?: any[] | null }) => {
  const router = useRouter();
  const [savedClasses, setSavedClasses] = useState<any[]>([]); // You can replace any[] with your class type if defined
  const loadIDRef = React.useRef(0);

  const loadSavedClasses = useCallback(async (active?: { current: boolean }) => {
      const loadID = ++loadIDRef.current;
      try {
        const storageKey = `savedClasses-${selectedGrade}`;
        const stored = await getAccountScopedItem(storageKey);
        const parsed = stored ? JSON.parse(stored) : [];
        if ((!active || active.current) && loadID === loadIDRef.current) setSavedClasses(parsed);
      } catch (error) {
        console.error('Failed to load saved classes:', error);
      }
  }, [selectedGrade]);

  useFocusEffect(useCallback(() => {
    const active = { current: true };
    void loadSavedClasses(active);
    return () => { active.current = false; };
  }, [loadSavedClasses]));

  useEffect(() => {
    const listener = DeviceEventEmitter.addListener('manualGradesChanged', () => {
      void loadSavedClasses();
    });
    return () => listener.remove();
  }, [loadSavedClasses]);

  useEffect(() => {
    const invalid = DeviceEventEmitter.addListener('credentialsInvalid', () => {
      loadIDRef.current += 1;
      setSavedClasses([]);
    });
    const added = DeviceEventEmitter.addListener('credentialsAdded', () => {
      void loadSavedClasses();
    });
    return () => {
      invalid.remove();
      added.remove();
    };
  }, [loadSavedClasses]);
  

  return (
    !minimized ? (
      <View className="flex-1 mt-2 px-6">
        <View className="bg-cardColor rounded-2xl p-6 border border-dashed border-highlightText shadow-md flex items-center justify-center space-y-4">
          <Text className="text-main text-lg mb-3 text-center">
            Enter your {selectedGrade} year grades.
          </Text>
          <TouchableOpacity
            onPress={() => router.push({
              pathname: '/enterGrades/[gradeLevel]',
              params: {
                gradeLevel: selectedGrade,
                preloadedClasses: JSON.stringify(savedClasses),
                unifiedCourses: rawCourses ? JSON.stringify(rawCourses) : undefined,
              }
            })}
            activeOpacity={0.8}
            className="bg-highlight px-6 py-2 rounded-full shadow-lg"
          >
            <Text className="text-highlightText font-semibold text-base text-center">
              Enter Grades
            </Text>
          </TouchableOpacity>
        </View>
      </View>
    ) : (
      <TouchableOpacity
        onPress={() => router.push({
          pathname: '/enterGrades/[gradeLevel]',
          params: {
            gradeLevel: selectedGrade,
            preloadedClasses: JSON.stringify(savedClasses),
            unifiedCourses: rawCourses ? JSON.stringify(rawCourses) : undefined,
          }
        })}
        activeOpacity={0.7}
        className="bg-cardColor rounded-xl border border-dashed border-highlightText px-4 py-2 flex-row items-center justify-between"
        style={{ height: 50 }}
      >
        <Text className="text-main text-lg">
          Review your {selectedGrade} year grades
        </Text>
        <Ionicons name="chevron-forward" size={24} color="#cbd5e1" />
      </TouchableOpacity>
    )
  );
};

export default ManualGradeEntryCard;
