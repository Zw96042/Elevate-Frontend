// lib/authHandler.ts
import AsyncStorage from '@react-native-async-storage/async-storage';

interface AuthResult {
  success: boolean;
  error?: string;
}

export async function authenticate(): Promise<AuthResult> {
  try {
    const [link, username, password] = await Promise.all([
      AsyncStorage.getItem('skywardLink'),
      AsyncStorage.getItem('skywardUser'),
      AsyncStorage.getItem('skywardPass'),
    ]);

    if (!link || !username || !password) {
      return { success: false, error: 'Missing credentials' };
    }

    const response = await fetch('http://192.168.1.136:3000/auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ baseUrl: link, user: username, pass: password }),
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
    await AsyncStorage.setItem('baseUrl', link);

    return { success: true };
  } catch (err: any) {
    return { success: false, error: err.message || 'Unknown error' };
  }
}