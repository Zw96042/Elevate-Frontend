import AsyncStorage from '@react-native-async-storage/async-storage';

const ACCOUNT_DATA_KEYS = [
  'unifiedCourseData',
  'unifiedCourseDataTimestamp',
  'cachedInboxMessages',
  'cachedInboxTimestamp',
  'gradeLevelCache',
] as const;

const ACCOUNT_DATA_PREFIXES = ['gradeInfo_', 'gradeInfoTimestamp_'] as const;
const INBOX_CACHE_KEYS = ['cachedInboxMessages', 'cachedInboxTimestamp'] as const;

let accountGeneration = 0;
const pendingWrites = new Set<Promise<void>>();

export function getAccountDataGeneration(): number {
  return accountGeneration;
}

export function isAccountDataCurrent(generation: number): boolean {
  return generation === accountGeneration;
}

export function isLatestAccountRequest(
  generation: number,
  requestID: number,
  latestRequestID: number
): boolean {
  return isAccountDataCurrent(generation) && requestID === latestRequestID;
}

/**
 * Invalidates every in-flight account read synchronously, waits for any cache
 * write that already started, then removes only server-derived account data.
 * User preferences and manually entered what-if grades are deliberately kept.
 */
export async function invalidateAccountDataCache(): Promise<void> {
  accountGeneration += 1;
  await Promise.allSettled([...pendingWrites]);

  const allKeys = await AsyncStorage.getAllKeys();
  const derivedKeys = allKeys.filter(key =>
    ACCOUNT_DATA_PREFIXES.some(prefix => key.startsWith(prefix))
  );
  await AsyncStorage.multiRemove([...ACCOUNT_DATA_KEYS, ...derivedKeys]);
}

export async function writeAccountDataCache(
  entries: [string, string][],
  generation: number
): Promise<boolean> {
  if (!isAccountDataCurrent(generation)) return false;

  const write = AsyncStorage.multiSet(entries);
  pendingWrites.add(write);
  try {
    await write;
  } finally {
    pendingWrites.delete(write);
  }
  return isAccountDataCurrent(generation);
}

export async function clearInboxDataCache(): Promise<void> {
  await Promise.allSettled([...pendingWrites]);
  await AsyncStorage.multiRemove([...INBOX_CACHE_KEYS]);
}
