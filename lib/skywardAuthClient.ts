// This file contains the Skyward AUTH logic migrated from the backend to the frontend.
// It is designed for use in a React Native/Expo environment.
// Node.js-specific code has been removed or replaced.


import axios from 'axios';
import { parse } from 'node-html-parser';

export interface SkywardSessionCodes {
  dwd: string;
  wfaacl: string;
  encses: string;
  'User-Type': string;
  sessionid: string;
}

export interface SkywardLoginParams {
  username: string;
  password: string;
  baseURL: string;
}

/**
 * Authenticate with Skyward and get session codes.
 * @param username Username
 * @param password Password
 * @param baseURL Skyward base URL (should end with /)
 */
export async function getNewSessionCodes({ username, password, baseURL }: SkywardLoginParams): Promise<SkywardSessionCodes> {
  if (!baseURL || typeof baseURL !== 'string') {
    throw new Error('Invalid baseURL provided');
  }
  const cleanBaseURL = baseURL.endsWith('/') ? baseURL : baseURL + '/';
  const authenticationURL = cleanBaseURL + 'skyporthttp.w';
  try {
    new URL(authenticationURL);
  } catch (error) {
    throw new Error(`Invalid authentication URL: ${authenticationURL}`);
  }
  const formData = new URLSearchParams({
    codeType: 'tryLogin',
    login: username,
    password: password,
    requestAction: 'eel',
  });
  const response = await axios.post(authenticationURL, formData.toString(), {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  });
  const parsed = parsePostResponse(response.data);
  if (!parsed) {
    throw new Error('Failed to parse Skyward session codes.');
  }
  return parsed;
}

/**
 * Parse login response string.
 * @param postResponse The raw response string from login.
 */
export function parsePostResponse(postResponse: string): SkywardSessionCodes | null {
  if (!postResponse) return null;
  const dissectedString = postResponse.substring(4, postResponse.length - 5);
  const toks = dissectedString.split('^');
  if (toks.length < 15) {
    const root = parse(postResponse);
    const rootText = (root.text || postResponse || '').toLowerCase();
    if (rootText.includes('invalid username or password') || rootText.includes('invalid user') || rootText.includes('invalid login')) {
      throw new Error('Invalid user or pass, or locked account');
    }
    throw new Error(`Authentication parsing failed: ${rootText || 'Unknown error'}`);
  }
  return {
    dwd: toks[0],
    wfaacl: toks[3],
    encses: toks[14],
    'User-Type': toks[6],
    sessionid: `${toks[1]}\x15${toks[2]}`,
  };
}
