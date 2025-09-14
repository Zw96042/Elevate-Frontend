// Example usage of the Skyward AUTH logic in a React component or hook
import { useState } from 'react';
import { getNewSessionCodes, SkywardSessionCodes } from '../lib/skywardAuthClient';

export function useSkywardAuth() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sessionCodes, setSessionCodes] = useState<SkywardSessionCodes | null>(null);

  async function loginToSkyward({ username, password, baseURL }: { username: string; password: string; baseURL: string }) {
    setLoading(true);
    setError(null);
    setSessionCodes(null);
    try {
      const codes = await getNewSessionCodes({ username, password, baseURL });
      setSessionCodes(codes);
      return codes;
    } catch (err: any) {
      setError(err.message || 'Unknown error');
      return null;
    } finally {
      setLoading(false);
    }
  }

  return { loginToSkyward, loading, error, sessionCodes };
}

// Usage in a component:
// const { loginToSkyward, loading, error, sessionCodes } = useSkywardAuth();
// await loginToSkyward({ username, password, baseURL });
