import React from 'react';
import { renderHook, act, waitFor } from '@testing-library/react-native';
import { BottomSheetProvider, useBottomSheet } from '@/context/BottomSheetContext';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AppState } from 'react-native';

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () => ({
  getItem: jest.fn(),
  setItem: jest.fn(),
  multiSet: jest.fn(),
  multiGet: jest.fn(),
}));

// Mock getCurrentTerm
jest.mock('@/utils/academicCalendar', () => ({
  getCurrentTerm: jest.fn(() => 'Q3 Grades'),
  getAllTerms: jest.fn(() => ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades']),
}));

describe('BottomSheetContext', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);
    (AsyncStorage.multiSet as jest.Mock).mockResolvedValue(undefined);
  });

  it('should initialize with current term when no stored data', async () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <BottomSheetProvider>{children}</BottomSheetProvider>
    );

    const { result } = renderHook(() => useBottomSheet(), { wrapper });

    await waitFor(() => {
      expect(result.current.selectedCategory).toBe('Q3 Grades');
    });
  });

  it('should restore user-selected term on same day', async () => {
    const today = new Date().toDateString();
    (AsyncStorage.getItem as jest.Mock).mockImplementation((key: string) => {
      if (key === '@elevate_selected_term') return Promise.resolve('Q1 Grades');
      if (key === '@elevate_last_term_check') return Promise.resolve(today);
      if (key === '@elevate_user_term_override') return Promise.resolve('true');
      return Promise.resolve(null);
    });

    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <BottomSheetProvider>{children}</BottomSheetProvider>
    );

    const { result } = renderHook(() => useBottomSheet(), { wrapper });

    await waitFor(() => {
      expect(result.current.selectedCategory).toBe('Q1 Grades');
    });
  });

  it('should update to current term on new day without user override', async () => {
    const yesterday = new Date(Date.now() - 86400000).toDateString();
    (AsyncStorage.getItem as jest.Mock).mockImplementation((key: string) => {
      if (key === '@elevate_selected_term') return Promise.resolve('Q1 Grades');
      if (key === '@elevate_last_term_check') return Promise.resolve(yesterday);
      if (key === '@elevate_user_term_override') return Promise.resolve('false');
      return Promise.resolve(null);
    });

    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <BottomSheetProvider>{children}</BottomSheetProvider>
    );

    const { result } = renderHook(() => useBottomSheet(), { wrapper });

    await waitFor(() => {
      expect(result.current.selectedCategory).toBe('Q3 Grades');
    });
  });

  it('should save user selection with override flag', async () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <BottomSheetProvider>{children}</BottomSheetProvider>
    );

    const { result } = renderHook(() => useBottomSheet(), { wrapper });

    await waitFor(() => {
      expect(result.current.selectedCategory).toBe('Q3 Grades');
    });

    act(() => {
      result.current.setSelectedCategory('Q4 Grades');
    });

    await waitFor(() => {
      expect(AsyncStorage.multiSet).toHaveBeenCalledWith(
        expect.arrayContaining([
          ['@elevate_selected_term', 'Q4 Grades'],
          ['@elevate_user_term_override', 'true']
        ])
      );
    });
  });
});
