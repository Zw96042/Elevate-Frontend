import React from 'react';
import { act, renderHook, waitFor } from '@testing-library/react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { SettingSheetProvider } from '@/context/SettingSheetContext';
import { UnifiedDataProvider, useUnifiedData } from '@/context/UnifiedDataContext';
import { DataService } from '@/lib/services';
import { invalidateAccountDataCache } from '@/lib/utils/account-data-cache';

jest.mock('@/lib/services', () => ({
  DataService: {
    getCombinedData: jest.fn(),
    clearCache: jest.fn(),
  },
}));

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: {
    getAllKeys: jest.fn(async () => []),
    multiRemove: jest.fn(async () => undefined),
  },
}));

const getCombinedData = DataService.getCombinedData as jest.MockedFunction<
  typeof DataService.getCombinedData
>;

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(complete => { resolve = complete; });
  return { promise, resolve };
}

describe('UnifiedData account boundary', () => {
  it('does not let account A erase account B when A finishes last', async () => {
    const accountA = deferred<any>();
    const accountB = deferred<any>();
    getCombinedData
      .mockReturnValueOnce(accountA.promise)
      .mockReturnValueOnce(accountB.promise);

    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <SettingSheetProvider>
        <UnifiedDataProvider>{children}</UnifiedDataProvider>
      </SettingSheetProvider>
    );
    const { result } = renderHook(() => useUnifiedData(), { wrapper });
    await waitFor(() => expect(getCombinedData).toHaveBeenCalledTimes(1));

    await act(async () => { await invalidateAccountDataCache(); });
    let replacementRefresh!: Promise<void>;
    act(() => { replacementRefresh = result.current.refreshCourses(true); });
    await waitFor(() => expect(getCombinedData).toHaveBeenCalledTimes(2));

    accountB.resolve({
      success: true,
      courses: [{ courseName: 'Account B course' }],
      lastUpdated: '2026-08-12T13:00:00.000Z',
    });
    await act(async () => { await replacementRefresh; });
    expect(result.current.coursesData?.[0]?.courseName).toBe('Account B course');

    accountA.resolve({ success: false, error: 'Account changed while loading courses' });
    await act(async () => { await accountA.promise; await Promise.resolve(); });
    expect(result.current.coursesData?.[0]?.courseName).toBe('Account B course');
    expect(result.current.error).toBeNull();
    expect(AsyncStorage.multiRemove).toHaveBeenCalled();
  });
});
