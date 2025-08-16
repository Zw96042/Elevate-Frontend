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
  console.log('🔍 Starting loadReportCard...');
  
  // Test backend connectivity first
  try {
    console.log('🔗 Testing backend connectivity...');
    const testResponse = await fetch(`${config.BACKEND_IP}/`, { method: 'GET' });
    console.log('🔗 Backend connectivity test:', testResponse.status);
  } catch (connectError: any) {
    console.error('❌ Backend connectivity test failed:', connectError.message);
    return { courses: [], success: false, error: `Cannot connect to backend server: ${connectError.message}` };
  }
  
  const dwd = await AsyncStorage.getItem('dwd');
  const wfaacl = await AsyncStorage.getItem('wfaacl');
  const encses = await AsyncStorage.getItem('encses');
  const userType = await AsyncStorage.getItem('User-Type');
  const sessionid = await AsyncStorage.getItem('sessionid');
  const baseUrl = await AsyncStorage.getItem('baseUrl');

  console.log('🔑 Session credentials check:');
  console.log('- dwd:', dwd ? '✅ exists' : '❌ missing');
  console.log('- wfaacl:', wfaacl ? '✅ exists' : '❌ missing');
  console.log('- encses:', encses ? '✅ exists' : '❌ missing');
  console.log('- userType:', userType || 'using default');
  console.log('- sessionid:', sessionid ? '✅ exists' : '❌ missing');
  console.log('- baseUrl:', baseUrl || '❌ missing');

  const allSessionCodesExist = dwd && wfaacl && encses && userType && sessionid && baseUrl;

  if (!allSessionCodesExist) {
    console.log('⚠️ Missing session credentials, attempting authentication...');
    const authResult = await authenticate();
    if (!authResult.success) {
      console.error('❌ Authentication failed:', authResult.error);
      return { courses: [], success: false, error: authResult.error };
    }
    console.log('✅ Authentication successful, retrying...');
    return await loadReportCard(); // retry with new credentials
  }

  try {
    console.log('📞 Calling fetchSkywardReportCard...');
    const response = await fetchSkywardReportCard({ dwd, wfaacl, encses, userType, sessionid, baseUrl });
    
    console.log('📋 Raw API response:', response);
    
    if (response.success && response.data) {
      console.log('✅ Report card loaded successfully, courses count:', response.data.length);
      return { courses: response.data, success: true };
    } else {
      console.error('❌ API returned unsuccessful response:', response);
      return { courses: [], success: false, error: 'Failed to fetch report card data' };
    }
  } catch (error: any) {
    console.error('🚨 Error in loadReportCard:', error);
    console.error('🚨 Error message:', error.message);
    console.error('🚨 Error stack:', error.stack);
    
    if (error.message?.toLowerCase().includes('session expired')) {
      console.log('🔄 Session expired, attempting re-authentication...');
      const authResult = await authenticate();
      if (!authResult.success) {
        console.error('❌ Re-authentication failed:', authResult.error);
        return { courses: [], success: false, error: 'Re-authentication failed' };
      }
      console.log('✅ Re-authentication successful, retrying...');
      return await loadReportCard(); // retry after re-auth
    }
    return { courses: [], success: false, error: error.message };
  }
};
