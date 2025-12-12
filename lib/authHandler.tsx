
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
  const startTime = Date.now();
  const now = Date.now();
  
  // If we just authenticated recently AND it was successful, use cached result
  if (now - lastAuthTime < MIN_AUTH_INTERVAL && lastAuthResult?.success) {
    console.log(`⚡ Authentication: Using cached result (${Date.now() - startTime}ms)`);
    return lastAuthResult;
  }

  // If already authenticating, return the existing promise
  if (isAuthenticating && authPromise) {
    console.log('🔄 Authentication already in progress, waiting for existing request...');
    const waitStartTime = Date.now();
    const result = await authPromise;
    console.log(`⏱️ Authentication: Waited for existing request (${Date.now() - waitStartTime}ms)`);
    return result;
  }

  console.log('🚀 Authentication: Starting new authentication process...');
  
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
    const totalTime = Date.now() - startTime;
    console.log(`✅ Authentication: Complete (${totalTime}ms) - Success: ${result.success}`);
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
  const authStartTime = Date.now();
  try {
    console.log('🔐 Authentication: Getting stored credentials...');
    const credStartTime = Date.now();
    const authInfo = await SkywardAuth.get();
    console.log(`📋 Authentication: Credentials retrieved (${Date.now() - credStartTime}ms)`);
    
    if (!authInfo?.link || !authInfo?.username || !authInfo?.password) {
      console.log('❌ Authentication: Missing credentials');
      return { success: false, error: 'Missing credentials' };
    }
    
    if (authInfo.username !== "dev-test" || authInfo.password !== "fgx") {
      // Use frontend Skyward login logic
      console.log('🌐 Authentication: Making Skyward login request...');
      let sessionCodes;
      const skywardStartTime = Date.now();
      try {
        sessionCodes = await getNewSessionCodes({ username: authInfo.username, password: authInfo.password, baseURL: authInfo.link });
        console.log(`✅ Authentication: Skyward login successful (${Date.now() - skywardStartTime}ms)`);
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
        console.error('❌ Authentication: Invalid session codes received:', sessionCodes);
        return { success: false, error: 'Invalid session codes received from Skyward' };
      }
      
      console.log('💾 Authentication: Saving session codes to AsyncStorage...');
      const storageStartTime = Date.now();
      await Promise.all([
        AsyncStorage.setItem('dwd', sessionCodes.dwd),
        AsyncStorage.setItem('wfaacl', sessionCodes.wfaacl),
        AsyncStorage.setItem('encses', sessionCodes.encses),
        AsyncStorage.setItem('User-Type', sessionCodes['User-Type']),
        AsyncStorage.setItem('sessionid', sessionCodes.sessionid),
        AsyncStorage.setItem('skywardBaseURL', authInfo.link)
      ]);
      console.log(`✅ Authentication: Session codes saved (${Date.now() - storageStartTime}ms)`);
    } else {
      // Special Creds
      console.log('🔧 Authentication: Using development credentials...');
      const devStorageStartTime = Date.now();
      await Promise.all([
        AsyncStorage.setItem('dwd', "dev"),
        AsyncStorage.setItem('wfaacl', "dev"),
        AsyncStorage.setItem('encses', "dev"),
        AsyncStorage.setItem('User-Type', "dev"),
        AsyncStorage.setItem('sessionid', "dev"),
        AsyncStorage.setItem('skywardBaseURL', authInfo.link)
      ]);
      console.log(`✅ Authentication: Development credentials saved (${Date.now() - devStorageStartTime}ms)`);
    }
    
    const totalAuthTime = Date.now() - authStartTime;
    console.log(`🎉 Authentication: Process complete (${totalAuthTime}ms)`);
    return { success: true };
  } catch (err: any) {
    const totalAuthTime = Date.now() - authStartTime;
    console.error(`❌ Authentication: Error after ${totalAuthTime}ms:`, err.message);
    return { success: false, error: err.message || 'Unknown error' };
  }
}