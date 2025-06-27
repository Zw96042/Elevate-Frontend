import React, { createContext, useContext, useRef, useState, ReactNode } from 'react';
import SettingSheet from '@gorhom/bottom-sheet';

type SettingSheetContextType = {
  settingSheetRef: React.RefObject<React.ElementRef<typeof SettingSheet> | null>;
  link: string;
  setLink: React.Dispatch<React.SetStateAction<string>>;
  username: string;
  setUsername: React.Dispatch<React.SetStateAction<string>>;
  password: string;
  setPassword: React.Dispatch<React.SetStateAction<string>>;
};

const SettingSheetContext = createContext<SettingSheetContextType | undefined>(undefined);

export const SettingSheetProvider = ({ children }: { children: ReactNode }) => {
  const settingSheetRef = useRef<React.ElementRef<typeof SettingSheet> | null>(null);
  const [link, setLink] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  return (
    <SettingSheetContext.Provider value={{ settingSheetRef, link, setLink, username, setUsername, password, setPassword }}>
      {children}
    </SettingSheetContext.Provider>
  );
};

export const useSettingSheet = () => {
  const context = useContext(SettingSheetContext);
  if (!context) throw new Error('useSettingSheet must be used within SettingSheetProvider');
  return context;
};