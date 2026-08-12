import AsyncStorage from '@react-native-async-storage/async-storage';
import { getStoredSkywardCredentials } from './secure-skyward-storage';
import {
  ANONYMOUS_MANUAL_ACCOUNT,
  getActiveManualAccount,
  manualAccountKey,
  prepareManualAccount,
  setActiveManualAccount,
} from './manual-account-storage';

async function currentAccount(): Promise<string> {
  const activeAccount = getActiveManualAccount();
  if (activeAccount) {
    await prepareManualAccount(activeAccount);
    return activeAccount;
  }

  const credentials = await getStoredSkywardCredentials();
  const account = credentials?.accountIdentifier ?? ANONYMOUS_MANUAL_ACCOUNT;
  setActiveManualAccount(account);
  await prepareManualAccount(account);
  return account;
}

export async function getAccountScopedItem(baseKey: string): Promise<string | null> {
  const account = await currentAccount();
  return AsyncStorage.getItem(manualAccountKey(baseKey, account));
}

export async function setAccountScopedItem(baseKey: string, value: string): Promise<void> {
  const account = await currentAccount();
  await AsyncStorage.setItem(manualAccountKey(baseKey, account), value);
}

export async function removeAccountScopedItem(baseKey: string): Promise<void> {
  const account = await currentAccount();
  await AsyncStorage.removeItem(manualAccountKey(baseKey, account));
}
