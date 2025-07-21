import { useCallback, useEffect, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { DeviceEventEmitter } from 'react-native';

export type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

export const useGradeLevel = () => {
  const [currentGradeLevel, setCurrentGradeLevel] = useState<GradeLevel>('Freshman');

  const loadGrade = useCallback(async () => {
    const storedGrade = await AsyncStorage.getItem('gradeLevel');
    if (storedGrade && ['Freshman', 'Sophomore', 'Junior', 'Senior', 'All Time'].includes(storedGrade)) {
      setCurrentGradeLevel(storedGrade as GradeLevel);
    }
  }, []);

  useEffect(() => {
    loadGrade();

    const sub = DeviceEventEmitter.addListener('credentialsAdded', () => {
      loadGrade();
    });

    return () => sub.remove();
  }, [loadGrade]);

  return currentGradeLevel;
};