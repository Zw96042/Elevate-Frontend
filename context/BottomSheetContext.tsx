import React, { createContext, useContext, useRef, useState, ReactNode } from 'react';
import BottomSheet from '@gorhom/bottom-sheet';
import { getCurrentTerm, getAllTerms, type TermLabel } from '../utils/academicCalendar';

const terms: TermLabel[] = getAllTerms();

export type { TermLabel } from '../utils/academicCalendar';

type BottomSheetContextType = {
  bottomSheetRef: React.RefObject<React.ElementRef<typeof BottomSheet> | null>;
  selectedCategory: TermLabel;
  setSelectedCategory: React.Dispatch<React.SetStateAction<TermLabel>>;
};

const BottomSheetContext = createContext<BottomSheetContextType | undefined>(undefined);

export const BottomSheetProvider = ({ children }: { children: ReactNode }) => {
  const bottomSheetRef = useRef<React.ElementRef<typeof BottomSheet> | null>(null);
  const currentTerm = getCurrentTerm();
  console.log('📅 Auto-detected current term:', currentTerm, 'for date:', new Date().toLocaleDateString());
  const [selectedCategory, setSelectedCategory] = useState<TermLabel>(currentTerm);

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