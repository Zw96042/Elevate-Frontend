// lib/gradeInfoClient.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { authenticate } from './authHandler';

const config = require('./development.config.js');

export interface GradeInfoParams {
  stuId: string;
  corNumId: string;
  section: string;
  gbId: string;
  bucket: string;  // e.g. TERM 3, SEM 1
  customUrl?: string;
}

interface GradeInfoResult {
  success: boolean;
  data?: any;
  error?: string;
}

export const fetchGradeInfo = async (
  params: GradeInfoParams,
  retryCount: number = 0
): Promise<GradeInfoResult> => {
  try {
    if (retryCount > 1) {
      return { success: false, error: 'Max retry attempts reached' };
    }

    const dwd = await AsyncStorage.getItem('dwd');
    const wfaacl = await AsyncStorage.getItem('wfaacl');
    const encses = await AsyncStorage.getItem('encses');
    const sessionid = await AsyncStorage.getItem('sessionid');

    const allSessionCodesExist = dwd && wfaacl && encses && sessionid;

    if (!allSessionCodesExist) {
      const authResult = await authenticate();
      if (!authResult.success) {
        return { success: false, error: authResult.error };
      }
      return await fetchGradeInfo(params, retryCount + 1);
    }

    const response = await fetch(`${config.BACKEND_IP}/grade-info`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sessionTokens: {
          dwd,
          wfaacl,
          encses,
          'User-Type': '2',
          sessionid
        },
        params: {
          ...params,
          customUrl: "https://skyward-eisdprod.iscorp.com/scripts/wsisa.dll/WService=wsedueanesisdtx/",
        },
      }),
    });

    if (!response.ok || response.status === 401 || response.status === 400 || response.status === 500) {
        console.log("BAD");
      if ((response.status === 401 || response.status === 400 || response.status === 500) && retryCount === 0) {
        console.log('Session expired, retrying auth...');
        await AsyncStorage.multiRemove(['dwd', 'wfaacl', 'encses', 'sessionid']);
        const authResult = await authenticate();
        if (authResult.success) {
          return await fetchGradeInfo(params, retryCount + 1);
        } else {
          return { success: false, error: 'Re-authentication failed' };
        }
      } else {
        throw new Error(`Failed to fetch grade info: ${response.statusText}`);
      }
    }

    const responseData = await response.json();

    return { success: true, data: responseData };
  } catch (error: any) {
    console.error('Error fetching grade info:', error);
    return { success: false, error: error.message || 'Unknown error' };
  }
};