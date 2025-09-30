import AsyncStorage from '@react-native-async-storage/async-storage';
import { fetchSkywardReportCard } from './skywardClient';
import { authenticate } from './authHandler';
const config = require('./development.config.js');

interface ReportCardResult {
  courses: Course[];
  success: boolean;
  error?: string;
}

interface Course {
  course: number;
  courseName: string;
  instructor: string | null;
  period: number | null;
  time: string | null;
  scores: Array<{ bucket: string; score: number }>;
}

export const loadReportCard = async (): Promise<ReportCardResult> => {
  // Test backend connectivity first
  try {
    const testResponse = await fetch(`${config.BACKEND_IP}/`, { method: 'GET' });
  } catch (connectError: any) {
    return { courses: [], success: false, error: `Cannot connect to backend server: ${connectError.message}` };
  }
  
  const dwd = await AsyncStorage.getItem('dwd');
  const wfaacl = await AsyncStorage.getItem('wfaacl');
  const encses = await AsyncStorage.getItem('encses');
  const userType = await AsyncStorage.getItem('User-Type');
  const sessionid = await AsyncStorage.getItem('sessionid');
  const baseUrl = await AsyncStorage.getItem('skywardBaseURL');

  const allSessionCodesExist = dwd && wfaacl && encses && userType && sessionid && baseUrl;

  if (!allSessionCodesExist) {
    const authResult = await authenticate();
    if (!authResult.success) {
      return { courses: [], success: false, error: authResult.error };
    }
    return await loadReportCard(); // retry with new credentials
  }

  try {
    const response = await fetchSkywardReportCard({ dwd, wfaacl, encses, userType, sessionid, baseUrl });
    
    if (response.success && response.data) {
      return { courses: response.data, success: true };
    } else {
      return { courses: [], success: false, error: 'Failed to fetch report card data' };
    }
  } catch (error: any) {
    
    if (error.message?.toLowerCase().includes('session expired')) {
      const authResult = await authenticate();
      if (!authResult.success) {
        return { courses: [], success: false, error: 'Re-authentication failed' };
      }
      return await loadReportCard(); // retry after re-auth
    }
    return { courses: [], success: false, error: error.message };
  }
};
