// lib/authHandler.ts
import AsyncStorage from '@react-native-async-storage/async-storage';
import { SkywardAuth } from './skywardAuthInfo';
const config = require('./development.config.js');

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

    const response = await fetch(`${config.BACKEND_IP}/auth`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ baseUrl: authInfo.link, user: authInfo.username, pass: authInfo.password }),
    });

    if (!response.ok) {
      return { success: false, error: 'Authentication failed' };
    }

    const sessionCodes = await response.json();

    await AsyncStorage.setItem('dwd', sessionCodes.dwd);
    await AsyncStorage.setItem('wfaacl', sessionCodes.wfaacl);
    await AsyncStorage.setItem('encses', sessionCodes.encses);
    await AsyncStorage.setItem('User-Type', sessionCodes['User-Type']);
    await AsyncStorage.setItem('sessionid', sessionCodes.sessionid);
    await AsyncStorage.setItem('baseUrl', authInfo.link);

    return { success: true };
  } catch (err: any) {
    return { success: false, error: err.message || 'Unknown error' };
  }
}