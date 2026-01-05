// Hook for Skyward authentication using the new services layer
import { useState } from 'react';
import { AuthService, SessionManager } from '@/lib/services';
import { authenticateWithSkyward } from '@/lib/api';
import { SkywardSessionCodes } from '@/lib/types/api';

export function useSkywardAuth() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sessionCodes, setSessionCodes] = useState<SkywardSessionCodes | null>(null);

  async function loginToSkyward({ 
    username, 
    password, 
    baseURL 
  }: { 
    username: string; 
    password: string; 
    baseURL: string 
  }) {
    setLoading(true);
    setError(null);
    setSessionCodes(null);
    
    try {
      const codes = await authenticateWithSkyward({ username, password, baseURL });
      setSessionCodes(codes);
      
      // Save session codes
      await SessionManager.saveSessionCodes(codes, baseURL);
      
      return codes;
    } catch (err: any) {
      setError(err.message || 'Unknown error');
      return null;
    } finally {
      setLoading(false);
    }
  }

  async function logout() {
    await AuthService.clearSession();
    setSessionCodes(null);
  }

  return { 
    loginToSkyward, 
    logout,
    loading, 
    error, 
    sessionCodes 
  };
}
