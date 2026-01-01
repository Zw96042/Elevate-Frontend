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
  
  console.log('Skyward login response status:', JSON.stringify(postResponse.substring(0, 200)));
  
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
  
  // Find the first non-empty token to determine offset
  // Some responses have leading empty tokens (^^^^) which shifts all indices
  let offset = 0;
  while (offset < toks.length && toks[offset] === '') {
    offset++;
  }
  
  // Standard format (no offset): dwd at 0, wfaacl at 3, encses at 14, User-Type at 6, sessionid from 1+2
  // Offset format: all indices shifted by offset amount
  
  let dwd: string, wfaacl: string, encses: string, userType: string, sessionid: string;
  
  if (offset === 0) {
    // Standard format
    dwd = toks[0];
    wfaacl = toks[3];
    encses = toks[14];
    userType = toks[6];
    sessionid = `${toks[1]}\x15${toks[2]}`;
  } else {
    // Offset format - tokens are shifted
    // In offset format: dwd at offset, next values follow sequentially
    // Based on observed format: ^^^^dwd^sessionPart1^sessionPart2^wfaacl^...^userType^...^encses^...
    dwd = toks[offset] || '';
    const sessionPart1 = toks[offset + 1] || '';
    const sessionPart2 = toks[offset + 2] || '';
    wfaacl = toks[offset + 3] || '';
    userType = toks[offset + 4] || '2';
    
    // encses is typically at a fixed position from the end or at offset + 14 - offset = 14
    // Look for encses - it's usually a longer alphanumeric string
    // In the offset format, it appears to be at position 14 (absolute)
    encses = toks[14] || '';
    
    sessionid = `${sessionPart1}\x15${sessionPart2}`;
  }
  
  // Validate we got the essential codes
  if (!dwd || !wfaacl || !encses) {
    console.error('❌ Auth parsing: Missing essential session codes', { 
      dwd: !!dwd, wfaacl: !!wfaacl, encses: !!encses, 
      offset, tokensCount: toks.length,
      tokens: toks.slice(0, 20) // Log first 20 tokens for debugging
    });
    throw new Error('Failed to extract session codes from Skyward response');
  }
  
  console.log('✅ Successfully parsed session codes from response');
  
  return {
    dwd,
    wfaacl,
    encses,
    'User-Type': userType,
    sessionid,
  };
}