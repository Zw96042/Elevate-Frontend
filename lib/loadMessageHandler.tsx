import AsyncStorage from '@react-native-async-storage/async-storage';
import { fetchSkywardMessages } from './skywardClient';
import { authenticate } from './authHandler';

export const loadMessages = async (): Promise<{
  messages: Message[];
  credentialsSet: boolean;
}> => {
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
      return { messages: [], credentialsSet: false };
    }
    return await loadMessages(); // retry with new credentials
  }

  try {
    const data = await fetchSkywardMessages({ dwd, wfaacl, encses, userType, sessionid, baseUrl });
    const sorted = data.sort(
      (a: Message, b: Message) =>
        new Date(b.date).getTime() - new Date(a.date).getTime()
    );
    return { messages: sorted, credentialsSet: true };
  } catch (error: any) {
    console.error('Failed to fetch messages:', error.message);
    if (error.message?.toLowerCase().includes('session expired')) {
      const authResult = await authenticate();
      if (!authResult.success) {
        console.error('Re-authentication failed:', authResult.error);
        return { messages: [], credentialsSet: false };
      }
      return await loadMessages(); // retry after re-auth
    }
    return { messages: [], credentialsSet: true };
  }
};