import React, { createContext, useContext, useRef, useState, ReactNode } from 'react';
import BottomSheet from '@gorhom/bottom-sheet';

export type TermLabel = 'Q1 Grades' | 'Q2 Grades' | 'SM1 Grade' | 'Q3 Grades' | 'Q4 Grades' | 'SM2 Grades';

const terms: TermLabel[] = ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades']

type BottomSheetContextType = {
  bottomSheetRef: React.RefObject<React.ElementRef<typeof BottomSheet> | null>;
  selectedCategory: TermLabel;
  setSelectedCategory: React.Dispatch<React.SetStateAction<TermLabel>>;
};

const BottomSheetContext = createContext<BottomSheetContextType | undefined>(undefined);

export const BottomSheetProvider = ({ children }: { children: ReactNode }) => {
  const bottomSheetRef = useRef<React.ElementRef<typeof BottomSheet> | null>(null);
  const [selectedCategory, setSelectedCategory] = useState<TermLabel>('Q1 Grades');

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