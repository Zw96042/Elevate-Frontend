import React, { createContext, useContext, useRef, useState, ReactNode } from 'react';
import SettingSheet from '@gorhom/bottom-sheet';

export type TermLabel = 'Q1 Grades' | 'Q2 Grades' | 'SM1 Grade' | 'Q3 Grades' | 'Q4 Grades' | 'SM2 Grades';

const terms: TermLabel[] = ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades']

type SettingSheetContextType = {
  settingSheetRef: React.RefObject<React.ElementRef<typeof SettingSheet> | null>;
};

const SettingSheetContext = createContext<SettingSheetContextType | undefined>(undefined);

export const SettingSheetProvider = ({ children }: { children: ReactNode }) => {
  const settingSheetRef = useRef<React.ElementRef<typeof SettingSheet> | null>(null);
  const [selectedCategory, setSelectedCategory] = useState<TermLabel>('Q1 Grades');

  return (
    <SettingSheetContext.Provider value={{ settingSheetRef: settingSheetRef }}>
      {children}
    </SettingSheetContext.Provider>
  );
};

export const useSettingSheet = () => {
  const context = useContext(SettingSheetContext);
  if (!context) throw new Error('useSettingSheet must be used within SettingSheetProvider');
  return context;
};