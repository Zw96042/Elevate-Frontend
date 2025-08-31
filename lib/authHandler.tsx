// lib/authHandler.ts
import AsyncStorage from '@react-native-async-storage/async-storage';
import { SkywardAuth } from './skywardAuthInfo';
import { DeviceEventEmitter } from 'react-native';
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

    if (authInfo.username != "dev-test" || authInfo.password != "fgx") {
      const response = await fetch(`${config.BACKEND_IP}/auth`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ baseUrl: authInfo.link, user: authInfo.username, pass: authInfo.password }),
      });

      // console.log("RESPONSE: ", JSON.stringify(response, null, 1));
      
      if (!response.ok) {
        console.error(`Authentication request failed with status: ${response.status}`);
        const errorText = await response.text();
        console.error('Auth error response:', errorText);
        
        await AsyncStorage.setItem('dwd', "");
        await AsyncStorage.setItem('wfaacl', "");
        await AsyncStorage.setItem('encses',"");
        await AsyncStorage.setItem('User-Type', "");
        await AsyncStorage.setItem('sessionid', "");
        await AsyncStorage.setItem('baseUrl', authInfo.link);
        
        DeviceEventEmitter.emit('credentialsInvalid');

        return { success: false, error: `Authentication failed: ${response.status} - ${errorText}` };
      }

      const sessionCodes = await response.json();

      if (!sessionCodes || !sessionCodes.dwd || !sessionCodes.wfaacl || !sessionCodes.encses) {
        console.error('Invalid session codes received:', sessionCodes);
        return { success: false, error: 'Invalid session codes received from server' };
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