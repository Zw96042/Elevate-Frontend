import React, { createContext, useContext, useRef, useState, useEffect, ReactNode } from 'react';
import BottomSheet from '@gorhom/bottom-sheet';
import { getCurrentTerm, getAllTerms, type TermLabel } from '../utils/academicCalendar';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AppState } from 'react-native';

const terms: TermLabel[] = getAllTerms();

export type { TermLabel } from '../utils/academicCalendar';

type BottomSheetContextType = {
  bottomSheetRef: React.RefObject<React.ElementRef<typeof BottomSheet> | null>;
  selectedCategory: TermLabel;
  setSelectedCategory: React.Dispatch<React.SetStateAction<TermLabel>>;
};

const BottomSheetContext = createContext<BottomSheetContextType | undefined>(undefined);

const LAST_TERM_CHECK_KEY = '@elevate_last_term_check';
const SELECTED_TERM_KEY = '@elevate_selected_term';
const USER_OVERRIDE_KEY = '@elevate_user_term_override';

export const BottomSheetProvider = ({ children }: { children: ReactNode }) => {
  const bottomSheetRef = useRef<React.ElementRef<typeof BottomSheet> | null>(null);
  const currentTerm = getCurrentTerm();
  const [selectedCategory, setSelectedCategory] = useState<TermLabel>(currentTerm);
  const [isInitialized, setIsInitialized] = useState(false);

  // Initialize term selection from storage or current date
  useEffect(() => {
    const initializeTerm = async () => {
      try {
        const [storedTerm, lastCheck, userOverride] = await Promise.all([
          AsyncStorage.getItem(SELECTED_TERM_KEY),
          AsyncStorage.getItem(LAST_TERM_CHECK_KEY),
          AsyncStorage.getItem(USER_OVERRIDE_KEY)
        ]);

        const today = new Date().toDateString();
        const hasUserOverride = userOverride === 'true';

        // If user manually selected a term and we're still on the same day, keep their selection
        if (hasUserOverride && lastCheck === today && storedTerm) {
          console.log('📅 Restoring user-selected term:', storedTerm);
          setSelectedCategory(storedTerm as TermLabel);
        } else {
          // New day or no override - use current term based on date
          console.log('📅 Auto-detected current term:', currentTerm, 'for date:', new Date().toLocaleDateString());
          setSelectedCategory(currentTerm);
          await AsyncStorage.multiSet([
            [SELECTED_TERM_KEY, currentTerm],
            [LAST_TERM_CHECK_KEY, today],
            [USER_OVERRIDE_KEY, 'false']
          ]);
        }
      } catch (error) {
        console.error('Error initializing term:', error);
        setSelectedCategory(currentTerm);
      } finally {
        setIsInitialized(true);
      }
    };

    initializeTerm();
  }, []);

  // Check for term changes when app comes to foreground
  useEffect(() => {
    const subscription = AppState.addEventListener('change', async (nextAppState) => {
      if (nextAppState === 'active') {
        try {
          const [lastCheck, userOverride] = await Promise.all([
            AsyncStorage.getItem(LAST_TERM_CHECK_KEY),
            AsyncStorage.getItem(USER_OVERRIDE_KEY)
          ]);

          const today = new Date().toDateString();
          const hasUserOverride = userOverride === 'true';

          // If it's a new day and user hasn't manually overridden, update to current term
          if (lastCheck !== today && !hasUserOverride) {
            const newTerm = getCurrentTerm();
            console.log('📅 New day detected, updating to current term:', newTerm);
            setSelectedCategory(newTerm);
            await AsyncStorage.multiSet([
              [SELECTED_TERM_KEY, newTerm],
              [LAST_TERM_CHECK_KEY, today],
              [USER_OVERRIDE_KEY, 'false']
            ]);
          }
        } catch (error) {
          console.error('Error checking term on app resume:', error);
        }
      }
    });

    return () => {
      subscription.remove();
    };
  }, []);

  // Wrap setSelectedCategory to track user overrides
  const handleSetSelectedCategory = async (value: TermLabel | ((prev: TermLabel) => TermLabel)) => {
    const newTerm = typeof value === 'function' ? value(selectedCategory) : value;
    setSelectedCategory(newTerm);
    
    try {
      const today = new Date().toDateString();
      await AsyncStorage.multiSet([
        [SELECTED_TERM_KEY, newTerm],
        [LAST_TERM_CHECK_KEY, today],
        [USER_OVERRIDE_KEY, 'true'] // Mark as user override
      ]);
      console.log('📅 User manually selected term:', newTerm);
    } catch (error) {
      console.error('Error saving term selection:', error);
    }
  };

  return (
    <BottomSheetContext.Provider value={{ bottomSheetRef, selectedCategory, setSelectedCategory }}>
      {children}
    </BottomSheetContext.Provider>
  );
};

export const useBottomSheet = () => {
  const context = useContext(BottomSheetContext);
  if (!context) throw new Error('useBottomSheet must be used within BottomSheetProvider');
  return context;
};