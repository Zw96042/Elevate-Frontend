import AsyncStorage from '@react-native-async-storage/async-storage';
import { fetchSkywardMessages } from './skywardClient';
import { authenticate } from './authHandler';

interface messageResult {
  messages: Message[];
  success: boolean;
  error?: string;
}

export const loadMessages = async (): Promise<messageResult> => {
  const dwd = await AsyncStorage.getItem('dwd');
  const wfaacl = await AsyncStorage.getItem('wfaacl');
  const encses = await AsyncStorage.getItem('encses');
  const userType = await AsyncStorage.getItem('User-Type');
  const sessionid = await AsyncStorage.getItem('sessionid');
  const baseUrl = await AsyncStorage.getItem('baseUrl');

  const allSessionCodesExist = dwd && wfaacl && encses && userType && sessionid && baseUrl;

  if (!allSessionCodesExist) {
    const authResult = await authenticate();
    if (!authResult.success) {
      console.error('Authentication failed:', authResult.error);
      return { messages: [], success: false, error: authResult.error };
    }
    return await loadMessages(); // retry with new credentials
  }

  try {
    const data = await fetchSkywardMessages({ dwd, wfaacl, encses, userType, sessionid, baseUrl });
    const sorted = data.sort(
      (a: Message, b: Message) =>
        new Date(b.date).getTime() - new Date(a.date).getTime()
    );
    return { messages: sorted, success: true};
  } catch (error: any) {
    console.error('Failed to fetch messages:', error.message);
    if (error.message?.toLowerCase().includes('session expired')) {
      const authResult = await authenticate();
      if (!authResult.success) {
        console.error('Re-authentication failed:', authResult.error);
        return { messages: [], success: false};
      }
      return await loadMessages(); // retry after re-auth
    }
    return { messages: [], success: false};
  }
};