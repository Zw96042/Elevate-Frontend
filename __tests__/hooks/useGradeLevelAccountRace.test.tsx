import { act, renderHook, waitFor } from '@testing-library/react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useGradeLevel } from '@/hooks/useGradeLevel';
import { SkywardAuth } from '@/lib';
import { invalidateAccountDataCache } from '@/lib/utils/account-data-cache';

jest.mock('@/lib', () => ({
  SkywardAuth: { hasCredentials: jest.fn() },
}));

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: {
    getItem: jest.fn(async () => null),
    removeItem: jest.fn(async () => undefined),
    getAllKeys: jest.fn(async () => []),
    multiSet: jest.fn(async () => undefined),
    multiRemove: jest.fn(async () => undefined),
  },
}));

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(complete => { resolve = complete; });
  return { promise, resolve };
}

describe('grade-level account ownership', () => {
  it('does not let account A overwrite equal-sized account B data after invalidation', async () => {
    const accountA = deferred<boolean>();
    (SkywardAuth.hasCredentials as jest.Mock).mockReturnValueOnce(accountA.promise);
    const { result } = renderHook(() => useGradeLevel());
    await waitFor(() => expect(SkywardAuth.hasCredentials).toHaveBeenCalled());

    await act(async () => { await invalidateAccountDataCache(); });
    await act(async () => {
      await result.current.loadGradeFromCourseData([
        { courseName: 'Account B', gradeYear: 11 },
      ]);
    });
    expect(result.current.currentGradeLevel).toBe('Junior');

    accountA.resolve(false);
    await act(async () => { await accountA.promise; await Promise.resolve(); });

    expect(result.current.currentGradeLevel).toBe('Junior');
    expect(AsyncStorage.multiSet).toHaveBeenCalled();
  });
});
