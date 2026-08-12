import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';
import * as Crypto from 'expo-crypto';
import { SkywardSessionCodes } from '../types/api';
import {
  ANONYMOUS_MANUAL_ACCOUNT,
  moveManualAccountData,
  prepareManualAccount,
  setActiveManualAccount,
} from './manual-account-storage';

export interface StoredSkywardCredentials {
  username: string;
  password: string;
  accountIdentifier: string;
}

// Accounts and JSON shapes match the native 2.0.4 stores. Expo appends
// `:no-auth` to these iOS service names, which the native update must migrate.
const CREDENTIALS_KEY = 'skyward';
const SESSION_CODES_KEY = 'current';
const LEGACY_CREDENTIAL_KEYS = ['skywardUser', 'skywardPass'] as const;
const LEGACY_SESSION_KEYS = ['dwd', 'wfaacl', 'encses', 'User-Type', 'sessionid'] as const;
const CREDENTIAL_OPTIONS = {
  keychainService: 'com.zacharywilson.elevate.skyward',
  keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
};
const SESSION_OPTIONS = {
  keychainService: 'com.zacharywilson.elevate.skyward.session',
  keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
};
let credentialOperation: Promise<void> = Promise.resolve();

export async function getStoredSkywardCredentials(): Promise<StoredSkywardCredentials | null> {
  return serializeCredentialOperation(readStoredSkywardCredentials);
}

async function readStoredSkywardCredentials(): Promise<StoredSkywardCredentials | null> {
  const stored = await readSecureValue(CREDENTIALS_KEY, CREDENTIAL_OPTIONS, isCredentials);
  if (stored) {
    const scoped = await ensureAccountIdentifier(stored);
    setActiveManualAccount(scoped.accountIdentifier);
    // A prior save may have committed Keychain before the anonymous manual
    // transfer completed. Retry that idempotent move on every cold read.
    await moveManualAccountData(ANONYMOUS_MANUAL_ACCOUNT, scoped.accountIdentifier);
    await prepareManualAccount(scoped.accountIdentifier);
    await AsyncStorage.multiRemove([...LEGACY_CREDENTIAL_KEYS]);
    return scoped;
  }

  const [username, password] = await Promise.all(
    LEGACY_CREDENTIAL_KEYS.map(key => AsyncStorage.getItem(key))
  );
  if (!username || !password) {
    if (username !== null || password !== null) {
      await AsyncStorage.multiRemove([...LEGACY_CREDENTIAL_KEYS]);
    }
    setActiveManualAccount(ANONYMOUS_MANUAL_ACCOUNT);
    await prepareManualAccount(ANONYMOUS_MANUAL_ACCOUNT);
    return null;
  }

  const accountIdentifier = await identifierForUsername(username);
  const credentials = { username, password, accountIdentifier };
  await writeSecureValue(CREDENTIALS_KEY, credentials, CREDENTIAL_OPTIONS);
  setActiveManualAccount(accountIdentifier);
  await prepareManualAccount(accountIdentifier);
  await AsyncStorage.multiRemove([...LEGACY_CREDENTIAL_KEYS]);
  return credentials;
}

export async function saveStoredSkywardCredentials(
  credentials: Pick<StoredSkywardCredentials, 'username' | 'password'>
): Promise<void> {
  return serializeCredentialOperation(() => writeStoredSkywardCredentials(credentials));
}

async function writeStoredSkywardCredentials(
  credentials: Pick<StoredSkywardCredentials, 'username' | 'password'>
): Promise<void> {
  const current = await readSecureValue(CREDENTIALS_KEY, CREDENTIAL_OPTIONS, isCredentials);
  if (current) {
    const currentScoped = await ensureAccountIdentifier(current);
    await prepareManualAccount(currentScoped.accountIdentifier);
  }

  const accountIdentifier = await identifierForUsername(credentials.username);
  await writeSecureValue(
    CREDENTIALS_KEY,
    { ...credentials, accountIdentifier },
    CREDENTIAL_OPTIONS
  );
  setActiveManualAccount(accountIdentifier);
  // Always retry the anonymous transfer. If a prior post-Keychain migration
  // was interrupted, the next successful save must still recover that data.
  // Only the first connection may claim unscoped legacy data; on replacement,
  // such data cannot safely be assumed to belong to the new account.
  if (!current) await prepareManualAccount(ANONYMOUS_MANUAL_ACCOUNT);
  await moveManualAccountData(ANONYMOUS_MANUAL_ACCOUNT, accountIdentifier);
  await prepareManualAccount(accountIdentifier);
  await AsyncStorage.multiRemove([...LEGACY_CREDENTIAL_KEYS]);
}

async function serializeCredentialOperation<T>(operation: () => Promise<T>): Promise<T> {
  const queued = credentialOperation.then(operation, operation);
  credentialOperation = queued.then(() => undefined, () => undefined);
  return queued;
}

export async function getStoredSessionCodes(): Promise<SkywardSessionCodes | null> {
  const stored = await readSecureValue(SESSION_CODES_KEY, SESSION_OPTIONS, isSessionCodes);
  if (stored) {
    await AsyncStorage.multiRemove([...LEGACY_SESSION_KEYS]);
    return stored;
  }

  const [dwd, wfaacl, encses, userType, sessionid] = await Promise.all(
    LEGACY_SESSION_KEYS.map(key => AsyncStorage.getItem(key))
  );
  if (!dwd || !wfaacl || !encses || !userType || !sessionid) {
    if ([dwd, wfaacl, encses, userType, sessionid].some(value => value !== null)) {
      await AsyncStorage.multiRemove([...LEGACY_SESSION_KEYS]);
    }
    return readSecureValue(SESSION_CODES_KEY, SESSION_OPTIONS, isSessionCodes);
  }

  const sessionCodes: SkywardSessionCodes = {
    dwd,
    wfaacl,
    encses,
    'User-Type': userType,
    sessionid,
  };
  await writeSecureValue(SESSION_CODES_KEY, sessionCodes, SESSION_OPTIONS);
  await AsyncStorage.multiRemove([...LEGACY_SESSION_KEYS]);
  return sessionCodes;
}

export async function saveStoredSessionCodes(sessionCodes: SkywardSessionCodes): Promise<void> {
  await writeSecureValue(SESSION_CODES_KEY, sessionCodes, SESSION_OPTIONS);
  await AsyncStorage.multiRemove([...LEGACY_SESSION_KEYS]);
}

export async function clearStoredSessionCodes(): Promise<void> {
  await SecureStore.deleteItemAsync(SESSION_CODES_KEY, SESSION_OPTIONS);
  await AsyncStorage.multiRemove([...LEGACY_SESSION_KEYS]);
}

async function readSecureValue<T>(
  key: string,
  options: SecureStore.SecureStoreOptions,
  validate: (value: unknown) => value is T
): Promise<T | null> {
  const encoded = await SecureStore.getItemAsync(key, options);
  if (encoded === null) return null;

  let value: unknown;
  try {
    value = JSON.parse(encoded);
  } catch {
    throw new Error('Secure Skyward data could not be decoded');
  }
  if (!validate(value)) {
    throw new Error('Secure Skyward data has an invalid format');
  }
  return value;
}

async function writeSecureValue(
  key: string,
  value: unknown,
  options: SecureStore.SecureStoreOptions
): Promise<void> {
  await SecureStore.setItemAsync(key, JSON.stringify(value), options);
}

function isCredentials(value: unknown): value is StoredSkywardCredentials {
  if (!isRecord(value)) return false;
  return (
    typeof value.username === 'string' &&
    typeof value.password === 'string' &&
    (value.accountIdentifier === undefined || typeof value.accountIdentifier === 'string')
  );
}

function isSessionCodes(value: unknown): value is SkywardSessionCodes {
  if (!isRecord(value)) return false;
  return (
    typeof value.dwd === 'string' &&
    typeof value.wfaacl === 'string' &&
    typeof value.encses === 'string' &&
    typeof value['User-Type'] === 'string' &&
    typeof value.sessionid === 'string'
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

async function ensureAccountIdentifier(
  credentials: StoredSkywardCredentials
): Promise<StoredSkywardCredentials> {
  if (credentials.accountIdentifier) return credentials;
  const accountIdentifier = await identifierForUsername(credentials.username);
  const scoped = { ...credentials, accountIdentifier };
  await writeSecureValue(CREDENTIALS_KEY, scoped, CREDENTIAL_OPTIONS);
  return scoped;
}

async function identifierForUsername(username: string): Promise<string> {
  const normalized = username.trim().toLowerCase();
  const digest = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    normalized
  );
  // Exact match for CredentialStore.accountIdentifier(for:) in native 2.1.
  return digest.slice(0, 24).toLowerCase();
}
