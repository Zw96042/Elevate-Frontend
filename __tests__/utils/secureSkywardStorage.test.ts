import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';
import * as ExpoCrypto from 'expo-crypto';
import {
  getStoredSessionCodes,
  getStoredSkywardCredentials,
  saveStoredSessionCodes,
  saveStoredSkywardCredentials,
} from '../../lib/utils/secure-skyward-storage';
import { getActiveManualAccount } from '../../lib/utils/manual-account-storage';

jest.mock('expo-secure-store', () => ({
  WHEN_UNLOCKED_THIS_DEVICE_ONLY: 1,
  getItemAsync: jest.fn(),
  setItemAsync: jest.fn(),
  deleteItemAsync: jest.fn(),
}));

jest.mock('expo-crypto', () => ({
  CryptoDigestAlgorithm: { SHA256: 'SHA-256' },
  digestStringAsync: jest.fn(async () => '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'),
}));

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: {
    getItem: jest.fn(),
    getAllKeys: jest.fn(),
    multiGet: jest.fn(),
    multiSet: jest.fn(),
    multiRemove: jest.fn(),
  },
}));

const secureGet = SecureStore.getItemAsync as jest.MockedFunction<typeof SecureStore.getItemAsync>;
const secureSet = SecureStore.setItemAsync as jest.MockedFunction<typeof SecureStore.setItemAsync>;
const legacyGet = AsyncStorage.getItem as jest.MockedFunction<typeof AsyncStorage.getItem>;
const legacyGetAllKeys = AsyncStorage.getAllKeys as jest.MockedFunction<typeof AsyncStorage.getAllKeys>;
const legacyMultiGet = AsyncStorage.multiGet as jest.MockedFunction<typeof AsyncStorage.multiGet>;
const legacyMultiSet = AsyncStorage.multiSet as jest.MockedFunction<typeof AsyncStorage.multiSet>;
const legacyRemove = AsyncStorage.multiRemove as jest.MockedFunction<typeof AsyncStorage.multiRemove>;

describe('secure Skyward storage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    secureGet.mockResolvedValue(null);
    secureSet.mockResolvedValue();
    legacyGet.mockResolvedValue(null);
    legacyGetAllKeys.mockResolvedValue([]);
    legacyMultiGet.mockResolvedValue([]);
    legacyMultiSet.mockResolvedValue();
    legacyRemove.mockResolvedValue();
  });

  it('migrates legacy credentials only after the secure write succeeds', async () => {
    legacyGet.mockImplementation(async key => {
      if (key === 'skywardUser') return 'student';
      if (key === 'skywardPass') return 'password';
      return null;
    });

    await expect(getStoredSkywardCredentials()).resolves.toEqual({
      username: 'student',
      password: 'password',
      accountIdentifier: '0123456789abcdef01234567',
    });
    expect(secureSet).toHaveBeenCalledWith(
      'skyward',
      JSON.stringify({
        username: 'student',
        password: 'password',
        accountIdentifier: '0123456789abcdef01234567',
      }),
      {
        keychainService: 'com.zacharywilson.elevate.skyward',
        keychainAccessible: 1,
      }
    );
    expect(legacyRemove).toHaveBeenCalledWith(['skywardUser', 'skywardPass']);
    const credentialWrite = secureSet.mock.calls.findIndex(call => call[0] === 'skyward');
    expect(secureSet.mock.invocationCallOrder[credentialWrite]).toBeLessThan(
      legacyRemove.mock.invocationCallOrder[0]
    );
  });

  it('does not remove legacy credentials when the secure write fails', async () => {
    legacyGet.mockImplementation(async key => (key === 'skywardUser' ? 'student' : 'password'));
    secureSet.mockRejectedValue(new Error('Keychain unavailable'));

    await expect(getStoredSkywardCredentials()).rejects.toThrow('Keychain unavailable');
    expect(legacyRemove).not.toHaveBeenCalled();
  });

  it('imports anonymous manual work when the no-credential check wins startup', async () => {
    const source = 'savedClasses-Freshman';
    legacyGetAllKeys.mockResolvedValue([source]);
    legacyMultiGet.mockResolvedValue([[source, '[{"className":"Biology"}]']]);

    await expect(getStoredSkywardCredentials()).resolves.toBeNull();

    expect(legacyMultiSet).toHaveBeenCalledWith([[
      'manual.account.anonymous.savedClasses-Freshman',
      '[{"className":"Biology"}]',
    ]]);
    expect(legacyRemove).toHaveBeenCalledWith([source]);
  });

  it('discards an incomplete plaintext credential record', async () => {
    legacyGet.mockImplementation(async key => (key === 'skywardUser' ? 'student' : null));

    await expect(getStoredSkywardCredentials()).resolves.toBeNull();
    expect(secureSet).not.toHaveBeenCalled();
    expect(legacyRemove).toHaveBeenCalledWith(['skywardUser', 'skywardPass']);
  });

  it('saves fresh credentials securely and removes only legacy secret keys', async () => {
    await saveStoredSkywardCredentials({ username: 'new-student', password: 'new-password' });

    expect(secureSet).toHaveBeenCalledTimes(1);
    expect(legacyRemove).toHaveBeenCalledWith(['skywardUser', 'skywardPass']);
  });

  it('retries an interrupted anonymous manual-data transfer on secure credential read', async () => {
    secureGet.mockResolvedValue(JSON.stringify({
      username: 'student',
      password: 'password',
      accountIdentifier: '0123456789abcdef01234567',
    }));
    const source = 'manual.account.anonymous.savedClasses-Freshman';
    legacyGetAllKeys.mockResolvedValue([source]);
    legacyMultiGet.mockResolvedValue([[source, '[{"className":"Biology"}]']]);

    await getStoredSkywardCredentials();

    expect(legacyMultiSet).toHaveBeenCalledWith([[
      'manual.account.0123456789abcdef01234567.savedClasses-Freshman',
      '[{"className":"Biology"}]',
    ]]);
    expect(legacyRemove).toHaveBeenCalledWith([source]);
  });

  it('serializes a stale credential read behind replacement activation', async () => {
    let finishRead!: (value: string) => void;
    const staleRead = new Promise<string>(resolve => { finishRead = resolve; });
    secureGet
      .mockReturnValueOnce(staleRead)
      .mockResolvedValueOnce(JSON.stringify({
        username: 'account-a',
        password: 'password-a',
        accountIdentifier: 'aaaaaaaaaaaaaaaaaaaaaaaa',
      }));
    (ExpoCrypto.digestStringAsync as jest.Mock).mockResolvedValueOnce(
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    );

    const readingA = getStoredSkywardCredentials();
    await Promise.resolve();
    const savingB = saveStoredSkywardCredentials({ username: 'account-b', password: 'password-b' });
    finishRead(JSON.stringify({
      username: 'account-a',
      password: 'password-a',
      accountIdentifier: 'aaaaaaaaaaaaaaaaaaaaaaaa',
    }));

    await Promise.all([readingA, savingB]);
    expect(getActiveManualAccount()).toBe('bbbbbbbbbbbbbbbbbbbbbbbb');
  });

  it('migrates all legacy session secrets into one secure value', async () => {
    const legacyValues: Record<string, string> = {
      dwd: 'dwd',
      wfaacl: 'wfaacl',
      encses: 'encses',
      'User-Type': 'guardian',
      sessionid: 'session',
    };
    legacyGet.mockImplementation(async key => legacyValues[key] ?? null);

    const session = await getStoredSessionCodes();

    expect(session).toEqual(legacyValues);
    expect(secureSet).toHaveBeenCalledWith(
      'current',
      JSON.stringify(legacyValues),
      {
        keychainService: 'com.zacharywilson.elevate.skyward.session',
        keychainAccessible: 1,
      }
    );
    expect(legacyRemove).toHaveBeenCalledWith([
      'dwd',
      'wfaacl',
      'encses',
      'User-Type',
      'sessionid',
    ]);
  });

  it('does not remove unrelated data when saving a fresh session', async () => {
    await saveStoredSessionCodes({
      dwd: 'dwd',
      wfaacl: 'wfaacl',
      encses: 'encses',
      'User-Type': 'guardian',
      sessionid: 'session',
    });

    expect(legacyRemove).toHaveBeenCalledTimes(1);
    expect(legacyRemove).toHaveBeenCalledWith([
      'dwd',
      'wfaacl',
      'encses',
      'User-Type',
      'sessionid',
    ]);
  });

  it('invalidates an incomplete plaintext session record', async () => {
    legacyGet.mockImplementation(async key => (key === 'dwd' ? 'orphaned-token' : null));

    await expect(getStoredSessionCodes()).resolves.toBeNull();
    expect(secureSet).not.toHaveBeenCalled();
    expect(legacyRemove).toHaveBeenCalledWith([
      'dwd',
      'wfaacl',
      'encses',
      'User-Type',
      'sessionid',
    ]);
  });
});
