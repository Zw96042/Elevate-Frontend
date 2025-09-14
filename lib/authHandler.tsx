
// lib/authHandler.ts
import AsyncStorage from '@react-native-async-storage/async-storage';
import { SkywardAuth } from './skywardAuthInfo';
import { DeviceEventEmitter } from 'react-native';
import { getNewSessionCodes } from './skywardAuthClient';

interface AuthResult {
  success: boolean;
  error?: string;
}

export async function authenticate(): Promise<AuthResult> {
  try {
    const authInfo = await SkywardAuth.get();
    if (!authInfo?.link || !authInfo?.username || !authInfo?.password) {
      return { success: false, error: 'Missing credentials' };
    }
    if (authInfo.username !== "dev-test" || authInfo.password !== "fgx") {
      // Use frontend Skyward login logic
      let sessionCodes;
      try {
        sessionCodes = await getNewSessionCodes({ username: authInfo.username, password: authInfo.password, baseURL: authInfo.link });
      } catch (err: any) {
        await AsyncStorage.setItem('dwd', "");
        await AsyncStorage.setItem('wfaacl', "");
        await AsyncStorage.setItem('encses', "");
        await AsyncStorage.setItem('User-Type', "");
        await AsyncStorage.setItem('sessionid', "");
        await AsyncStorage.setItem('baseUrl', authInfo.link);
        DeviceEventEmitter.emit('credentialsInvalid');
        return { success: false, error: err.message || 'Authentication failed' };
      }
      if (!sessionCodes || !sessionCodes.dwd || !sessionCodes.wfaacl || !sessionCodes.encses) {
        console.error('Invalid session codes received:', sessionCodes);
        return { success: false, error: 'Invalid session codes received from Skyward' };
      }
      await AsyncStorage.setItem('dwd', sessionCodes.dwd);
      await AsyncStorage.setItem('wfaacl', sessionCodes.wfaacl);
      await AsyncStorage.setItem('encses', sessionCodes.encses);
      await AsyncStorage.setItem('User-Type', sessionCodes['User-Type']);
      await AsyncStorage.setItem('sessionid', sessionCodes.sessionid);
      await AsyncStorage.setItem('baseUrl', authInfo.link);
    } else {
      // Special Creds
      await AsyncStorage.setItem('dwd', "dev");
      await AsyncStorage.setItem('wfaacl', "dev");
      await AsyncStorage.setItem('encses', "dev");
      await AsyncStorage.setItem('User-Type', "dev");
      await AsyncStorage.setItem('sessionid', "dev");
      await AsyncStorage.setItem('baseUrl', authInfo.link);
    }
    return { success: true };
  } catch (err: any) {
    return { success: false, error: err.message || 'Unknown error' };
  }
}