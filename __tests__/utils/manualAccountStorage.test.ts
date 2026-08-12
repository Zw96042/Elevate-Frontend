import {
  manualAccountKey,
  migrateLegacyManualData,
  moveManualAccountData,
} from '../../lib/utils/manual-account-storage';

const mockStorage = new Map<string, string>();

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: {
    getAllKeys: jest.fn(async () => [...mockStorage.keys()]),
    getItem: jest.fn(async (key: string) => mockStorage.get(key) ?? null),
    multiGet: jest.fn(async (keys: string[]) => keys.map(key => [key, mockStorage.get(key) ?? null])),
    multiSet: jest.fn(async (entries: [string, string][]) => {
      entries.forEach(([key, value]) => mockStorage.set(key, value));
    }),
    multiRemove: jest.fn(async (keys: string[]) => {
      keys.forEach(key => mockStorage.delete(key));
    }),
  },
}));

describe('manual academic data account scopes', () => {
  beforeEach(() => {
    mockStorage.clear();
    jest.clearAllMocks();
  });

  it('moves legacy manual data into only the active account namespace', async () => {
    mockStorage.set('savedClasses-Senior', '[{"name":"Physics"}]');
    mockStorage.set('artificialAssignments', '{"course-a":[]}');
    mockStorage.set('showoffMode', 'true');

    await migrateLegacyManualData('account-a');

    expect(mockStorage.get(manualAccountKey('savedClasses-Senior', 'account-a'))).toContain('Physics');
    expect(mockStorage.get(manualAccountKey('artificialAssignments', 'account-a'))).toBe('{"course-a":[]}');
    expect(mockStorage.has('savedClasses-Senior')).toBe(false);
    expect(mockStorage.has('artificialAssignments')).toBe(false);
    expect(mockStorage.get(manualAccountKey('savedClasses-Senior', 'account-b'))).toBeUndefined();
    expect(mockStorage.get('showoffMode')).toBe('true');
  });

  it('merges anonymous manual work on first account connection', async () => {
    mockStorage.set(manualAccountKey('savedClasses-Freshman', 'anonymous'), '[{"className":"Biology"}]');
    mockStorage.set(manualAccountKey('savedClasses-Freshman', 'account-a'), '[{"className":"Geometry"}]');

    await moveManualAccountData('anonymous', 'account-a');

    expect(JSON.parse(mockStorage.get(manualAccountKey('savedClasses-Freshman', 'account-a'))!))
      .toEqual([{ className: 'Geometry' }, { className: 'Biology' }]);
    expect(mockStorage.has(manualAccountKey('savedClasses-Freshman', 'anonymous'))).toBe(false);
  });

  it('retains a conflicting source record instead of deleting manual work', async () => {
    const source = manualAccountKey('savedClasses-Freshman', 'anonymous');
    const target = manualAccountKey('savedClasses-Freshman', 'account-a');
    mockStorage.set(source, '[{"className":"Biology","sm1":91}]');
    mockStorage.set(target, '[{"className":"Biology","sm1":95}]');

    await moveManualAccountData('anonymous', 'account-a');

    expect(mockStorage.get(target)).toContain('95');
    expect(mockStorage.get(source)).toContain('91');
  });
});
