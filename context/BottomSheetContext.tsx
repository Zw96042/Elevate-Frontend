import React, { createContext, useContext, useRef, useState, ReactNode } from 'react';
import BottomSheet from '@gorhom/bottom-sheet';

export type TermLabel = 'Q1 Grades' | 'Q2 Grades' | 'SM1 Grade' | 'Q3 Grades' | 'Q4 Grades' | 'SM2 Grades';

const terms: TermLabel[] = ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades']

// Function to determine current term based on date
const getCurrentTerm = (): TermLabel => {
  const now = new Date();
  const currentYear = now.getFullYear();
  
  // Define term date ranges (assuming school year starts in August)
  const termRanges = [
    {
      term: 'Q1 Grades' as TermLabel,
      start: new Date(currentYear, 7, 13), // August 13 (month is 0-indexed)
      end: new Date(currentYear, 9, 9),   // October 9
    },
    {
      term: 'Q2 Grades' as TermLabel,
      start: new Date(currentYear, 9, 14), // October 14
      end: new Date(currentYear, 11, 19),  // December 19
    },
    {
      term: 'Q3 Grades' as TermLabel,
      start: new Date(currentYear + 1, 0, 6), // January 6 (next year)
      end: new Date(currentYear + 1, 2, 13),  // March 13 (next year)
    },
    {
      term: 'Q4 Grades' as TermLabel,
      start: new Date(currentYear + 1, 2, 23), // March 23 (next year)
      end: new Date(currentYear + 1, 4, 22),   // May 22 (next year)
    },
  ];
  
  // Check if current date falls within any term range
  for (const { term, start, end } of termRanges) {
    if (now >= start && now <= end) {
      return term;
    }
  }
  
  // If no term matches (e.g., summer break), default to Q1 for the upcoming year
  // Check if we're in summer (after Q4 ends)
  const q4End = new Date(currentYear, 4, 22); // May 22 of current year
  if (now > q4End) {
    return 'Q1 Grades'; // Summer - default to next year's Q1
  }
  
  // If we're before Q1 starts (early summer), default to Q1
  return 'Q1 Grades';
};

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