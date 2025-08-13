import { useCallback, useEffect, useState } from 'react';
import { AcademicHistoryManager } from '@/lib/academicHistoryManager';
import { SkywardAuth } from '@/lib/skywardAuthInfo';

export type GradeLevel = 'Freshman' | 'Sophomore' | 'Junior' | 'Senior' | 'All Time';

// Convert grade number to grade level name
const getGradeLevelName = (gradeNumber: number): GradeLevel => {
  switch (gradeNumber) {
    case 9: return 'Freshman';
    case 10: return 'Sophomore';
    case 11: return 'Junior';
    case 12: return 'Senior';
    default: return 'Freshman';
  }
};

export const useGradeLevel = () => {
  const [currentGradeLevel, setCurrentGradeLevel] = useState<GradeLevel>('Freshman');
  const [availableGradeLevels, setAvailableGradeLevels] = useState<GradeLevel[]>(['Freshman']);

  const loadGradeFromAcademicHistory = useCallback(async () => {
    try {
      // Check if we have credentials first
      const hasCredentials = await SkywardAuth.hasCredentials();
      if (!hasCredentials) {
        // Fallback to stored grade level if no credentials
        return;
      }

      // Get academic history to determine current grade level
      const result = await AcademicHistoryManager.getAcademicHistory(false);
      if (result.success && result.currentGradeLevel && result.availableGradeLevels) {
        const currentGrade = getGradeLevelName(result.currentGradeLevel);
        setCurrentGradeLevel(currentGrade);
        
        // Convert available grade numbers to grade level names, plus "All Time"
        const availableGrades = result.availableGradeLevels.map(getGradeLevelName);
        if (availableGrades.length > 1) {
          availableGrades.push('All Time');
        }
        setAvailableGradeLevels(availableGrades);
      }
    } catch (error) {
      console.error('Error loading grade level from academic history:', error);
    }
  }, []);

  useEffect(() => {
    loadGradeFromAcademicHistory();
  }, [loadGradeFromAcademicHistory]);

  return { currentGradeLevel, availableGradeLevels };
};