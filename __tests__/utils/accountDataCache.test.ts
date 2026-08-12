import AsyncStorage from '@react-native-async-storage/async-storage';
import {
  getAccountDataGeneration,
  invalidateAccountDataCache,
  isLatestAccountRequest,
  writeAccountDataCache,
} from '../../lib/utils/account-data-cache';

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: {
    getAllKeys: jest.fn(),
    multiRemove: jest.fn(),
    multiSet: jest.fn(),
  },
}));

const getAllKeys = AsyncStorage.getAllKeys as jest.MockedFunction<typeof AsyncStorage.getAllKeys>;
const multiRemove = AsyncStorage.multiRemove as jest.MockedFunction<typeof AsyncStorage.multiRemove>;
const multiSet = AsyncStorage.multiSet as jest.MockedFunction<typeof AsyncStorage.multiSet>;

describe('account data cache boundary', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    getAllKeys.mockResolvedValue([
      'unifiedCourseData',
      'gradeInfo_old-student',
      'cachedInboxMessages',
      'artificialAssignments',
      'savedClasses-Senior',
      'showoffMode',
    ]);
    multiRemove.mockResolvedValue();
    multiSet.mockResolvedValue();
  });

  it('rejects writes from the prior account and preserves manual preferences', async () => {
    const oldGeneration = getAccountDataGeneration();
    await invalidateAccountDataCache();

    await expect(writeAccountDataCache([
      ['unifiedCourseData', 'student-a'],
    ], oldGeneration)).resolves.toBe(false);
    expect(multiSet).not.toHaveBeenCalled();

    const removed = multiRemove.mock.calls[0][0];
    expect(removed).toEqual(expect.arrayContaining([
      'unifiedCourseData',
      'gradeInfo_old-student',
      'cachedInboxMessages',
    ]));
    expect(removed).not.toContain('artificialAssignments');
    expect(removed).not.toContain('savedClasses-Senior');
    expect(removed).not.toContain('showoffMode');
  });

  it('ignores an old account completion after the replacement request wins', async () => {
    const oldGeneration = getAccountDataGeneration();
    const oldRequestID = 1;
    await invalidateAccountDataCache();
    const newGeneration = getAccountDataGeneration();
    const newRequestID = 2;

    expect(isLatestAccountRequest(newGeneration, newRequestID, newRequestID)).toBe(true);
    expect(isLatestAccountRequest(oldGeneration, oldRequestID, newRequestID)).toBe(false);
  });

  it('invalidates work that starts during a secure credential replacement', async () => {
    await invalidateAccountDataCache();
    const duringSecureWrite = getAccountDataGeneration();

    // Credential activation advances the boundary a second time.
    await invalidateAccountDataCache();

    await expect(writeAccountDataCache([
      ['unifiedCourseData', 'former-account'],
    ], duringSecureWrite)).resolves.toBe(false);
    expect(multiSet).not.toHaveBeenCalled();
  });
});
