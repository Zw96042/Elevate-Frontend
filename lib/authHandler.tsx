
// lib/authHandler.ts
import AsyncStorage from '@react-native-async-storage/async-storage';
import { SkywardAuth } from './skywardAuthInfo';
import { DeviceEventEmitter } from 'react-native';
import { getNewSessionCodes } from './skywardAuthClient';

interface AuthResult {
  success: boolean;
  error?: string;
}

// Global authentication state to prevent concurrent auth requests
let isAuthenticating = false;
let authPromise: Promise<AuthResult> | null = null;
let lastAuthTime = 0;
let lastAuthResult: AuthResult | null = null;
const MIN_AUTH_INTERVAL = 2000; // Minimum 2 seconds between auth attempts

export async function authenticate(): Promise<AuthResult> {
  const now = Date.now();
  
  // If we just authenticated recently AND it was successful, use cached result
  if (now - lastAuthTime < MIN_AUTH_INTERVAL && lastAuthResult?.success) {
    console.log('⏱️ Authentication attempted too recently, using cached result');
    return lastAuthResult;
  }

  // If already authenticating, return the existing promise
  if (isAuthenticating && authPromise) {
    console.log('🔄 Authentication already in progress, waiting for existing request...');
    return authPromise;
  }

  // Set authentication in progress
  isAuthenticating = true;
  lastAuthTime = now;
  
  // Create the authentication promise
  authPromise = performAuthentication();
  
  try {
    const result = await authPromise;
    lastAuthResult = result; // Cache the result
    if (result.success) {
      lastAuthTime = Date.now(); // Update timestamp on success
    }
    return result;
  } finally {
    // Reset authentication state after a delay to prevent immediate retries
    setTimeout(() => {
      isAuthenticating = false;
      authPromise = null;
    }, 1000);
  }
}

async function performAuthentication(): Promise<AuthResult> {
  try {
    console.log('🔐 Starting authentication process...');
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
        console.log('❌ Authentication failed:', err.message);
        await AsyncStorage.setItem('dwd', "");
        await AsyncStorage.setItem('wfaacl', "");
        await AsyncStorage.setItem('encses', "");
        await AsyncStorage.setItem('User-Type', "");
        await AsyncStorage.setItem('sessionid', "");
        await AsyncStorage.setItem('skywardBaseURL', authInfo.link);
        DeviceEventEmitter.emit('credentialsInvalid');
        return { success: false, error: err.message || 'Authentication failed' };
      }
      if (!sessionCodes || !sessionCodes.dwd || !sessionCodes.wfaacl || !sessionCodes.encses) {
        console.error('❌ Invalid session codes received:', sessionCodes);
        return { success: false, error: 'Invalid session codes received from Skyward' };
      }
      console.log('✅ Authentication successful, saving session codes...');
      await AsyncStorage.setItem('dwd', sessionCodes.dwd);
      await AsyncStorage.setItem('wfaacl', sessionCodes.wfaacl);
      await AsyncStorage.setItem('encses', sessionCodes.encses);
      await AsyncStorage.setItem('User-Type', sessionCodes['User-Type']);
      await AsyncStorage.setItem('sessionid', sessionCodes.sessionid);
      await AsyncStorage.setItem('skywardBaseURL', authInfo.link);
      console.log('✅ Session codes saved to AsyncStorage');
    } else {
      // Special Creds
      console.log('🔧 Using development credentials...');
      await AsyncStorage.setItem('dwd', "dev");
      await AsyncStorage.setItem('wfaacl', "dev");
      await AsyncStorage.setItem('encses', "dev");
      await AsyncStorage.setItem('User-Type', "dev");
      await AsyncStorage.setItem('sessionid', "dev");
      await AsyncStorage.setItem('skywardBaseURL', authInfo.link);
    }
    return { success: true };
  } catch (err: any) {
    console.error('❌ Authentication error:', err.message);
    return { success: false, error: err.message || 'Unknown error' };
  }
}