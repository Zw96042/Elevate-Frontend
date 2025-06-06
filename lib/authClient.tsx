// lib/authClient.ts
import AsyncStorage from '@react-native-async-storage/async-storage';

export const authenticateAndStoreSession = async (user: string, pass: string, baseUrl: string) => {
  const res = await fetch('http://192.168.1.136:3000/auth', {
    method: 'POST',
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ user, pass, baseUrl })
  });

  const data = await res.json();
  if (!res.ok || data.error) throw new Error(data.error || 'Authentication failed');

  // Store session tokens
  await AsyncStorage.multiSet([
    ['sessionid', data.sessionid],
    ['encses', data.encses],
    ['dwd', data.dwd],
    ['wfaacl', data.wfaacl]
  ]);

  return true;
};