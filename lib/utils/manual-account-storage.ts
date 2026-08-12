import AsyncStorage from '@react-native-async-storage/async-storage';

export const ANONYMOUS_MANUAL_ACCOUNT = 'anonymous';

const MANUAL_EXACT_KEYS = [
  'artificialAssignments',
  'finalExamGrades',
  'showCalculated',
] as const;
const MANUAL_PREFIXES = ['savedClasses-', 'showCalculated_'] as const;
const MANUAL_NAMESPACE = 'manual.account.';
let activeManualAccount: string | null = null;
const accountPreparations = new Map<string, Promise<void>>();

export function getActiveManualAccount(): string | null {
  return activeManualAccount;
}

export function setActiveManualAccount(accountIdentifier: string): void {
  activeManualAccount = accountIdentifier;
}

export function manualAccountKey(baseKey: string, accountIdentifier: string): string {
  return `${MANUAL_NAMESPACE}${accountIdentifier}.${baseKey}`;
}

export async function prepareManualAccount(accountIdentifier: string): Promise<void> {
  const existing = accountPreparations.get(accountIdentifier);
  if (existing) return existing;

  const preparation = migrateLegacyManualData(accountIdentifier).catch(error => {
    accountPreparations.delete(accountIdentifier);
    throw error;
  });
  accountPreparations.set(accountIdentifier, preparation);
  await preparation;
}

export async function migrateLegacyManualData(accountIdentifier: string): Promise<void> {
  const allKeys = await AsyncStorage.getAllKeys();
  const legacyKeys = allKeys.filter(key =>
    MANUAL_EXACT_KEYS.includes(key as typeof MANUAL_EXACT_KEYS[number]) ||
    MANUAL_PREFIXES.some(prefix => key.startsWith(prefix))
  );
  if (legacyKeys.length === 0) return;

  const legacyEntries = await AsyncStorage.multiGet(legacyKeys);
  const writes: [string, string][] = [];
  const removable: string[] = [];
  for (const [key, value] of legacyEntries) {
    if (value === null) continue;
    const scopedKey = manualAccountKey(key, accountIdentifier);
    const target = await AsyncStorage.getItem(scopedKey);
    if (target === null) {
      writes.push([scopedKey, value]);
      removable.push(key);
      continue;
    }
    const merged = mergeManualValues(key, value, target);
    if (merged.value !== target) writes.push([scopedKey, merged.value]);
    if (merged.complete) removable.push(key);
  }
  if (writes.length > 0) await AsyncStorage.multiSet(writes);
  if (removable.length > 0) await AsyncStorage.multiRemove(removable);
}

export async function moveManualAccountData(
  fromAccount: string,
  toAccount: string
): Promise<void> {
  if (fromAccount === toAccount) return;
  const fromPrefix = `${MANUAL_NAMESPACE}${fromAccount}.`;
  const allKeys = await AsyncStorage.getAllKeys();
  const sourceKeys = allKeys.filter(key => key.startsWith(fromPrefix));
  if (sourceKeys.length === 0) return;

  const entries = await AsyncStorage.multiGet(sourceKeys);
  const writes: [string, string][] = [];
  const removable: string[] = [];
  for (const [sourceKey, value] of entries) {
    if (value === null) continue;
    const baseKey = sourceKey.slice(fromPrefix.length);
    const targetKey = manualAccountKey(baseKey, toAccount);
    const target = await AsyncStorage.getItem(targetKey);
    if (target === null) {
      writes.push([targetKey, value]);
      removable.push(sourceKey);
      continue;
    }
    const merged = mergeManualValues(baseKey, value, target);
    if (merged.value !== target) writes.push([targetKey, merged.value]);
    if (merged.complete) removable.push(sourceKey);
  }
  if (writes.length > 0) await AsyncStorage.multiSet(writes);
  if (removable.length > 0) await AsyncStorage.multiRemove(removable);
}

function mergeManualValues(
  baseKey: string,
  sourceRaw: string,
  targetRaw: string
): { value: string; complete: boolean } {
  if (sourceRaw === targetRaw) return { value: targetRaw, complete: true };
  try {
    const source = JSON.parse(sourceRaw);
    const target = JSON.parse(targetRaw);
    if (baseKey.startsWith('savedClasses-') && Array.isArray(source) && Array.isArray(target)) {
      const merged = [...target];
      let complete = true;
      const targetByName = new Map(target.map(row => [manualClassName(row), row]));
      for (const row of source) {
        const name = manualClassName(row);
        const existing = targetByName.get(name);
        if (!existing) {
          merged.push(row);
          targetByName.set(name, row);
        } else if (JSON.stringify(existing) !== JSON.stringify(row)) {
          complete = false;
        }
      }
      return { value: JSON.stringify(merged), complete };
    }
    if (isRecord(source) && isRecord(target)) {
      const merged = { ...target };
      let complete = true;
      for (const [key, value] of Object.entries(source)) {
        if (!(key in target)) merged[key] = value;
        else if (JSON.stringify(target[key]) !== JSON.stringify(value)) complete = false;
      }
      return { value: JSON.stringify(merged), complete };
    }
  } catch {
    // Keep the source for a future/manual recovery when either value is corrupt.
  }
  return { value: targetRaw, complete: false };
}

function manualClassName(value: unknown): string {
  if (!isRecord(value)) return JSON.stringify(value);
  return String(value.className ?? value.courseName ?? value.name ?? JSON.stringify(value))
    .trim()
    .toLocaleLowerCase();
}

function isRecord(value: unknown): value is Record<string, any> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
