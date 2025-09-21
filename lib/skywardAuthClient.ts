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
  
  try {
    const response = await axios.post(authenticationURL, formData.toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });
    console.log('Skyward login response status:', JSON.stringify(response.data, null, 2));
    const parsed = parsePostResponse(response.data);
    if (!parsed) {
      throw new Error('Failed to parse Skyward session codes - the response format may have changed or the server may be experiencing issues.');
    }
    return parsed;
  } catch (error: any) {
    // If it's a network error but we have response data, try to parse it anyway
    if (error.response && error.response.data) {
      console.log('⚠️ Network error occurred but response data available, attempting to parse...');
      console.log('Response data:', JSON.stringify(error.response.data, null, 2));
      const parsed = parsePostResponse(error.response.data);
      if (parsed) {
        console.log('✅ Successfully recovered from network error with valid session codes');
        return parsed;
      }
    }
    
    // If we truly can't get valid session codes, throw the error
    throw error;
  }
}

/**
 * Parse login response string.
 * @param postResponse The raw response string from login.
 */
export function parsePostResponse(postResponse: string): SkywardSessionCodes | null {
  if (!postResponse) return null;
  
  // Handle responses wrapped in HTML tags (like <li>)
  let cleanResponse = postResponse;
  if (postResponse.includes('<li>') && postResponse.includes('</li>')) {
    const root = parse(postResponse);
    cleanResponse = root.text || postResponse;
  }
  
  // Try to extract session codes from the clean response
  const toks = cleanResponse.split('^');
  
  if (toks.length >= 15) {
    // Valid session codes found
    console.log('✅ Successfully parsed session codes from response');
    return {
      dwd: toks[0],
      wfaacl: toks[3],
      encses: toks[14],
      'User-Type': toks[6],
      sessionid: `${toks[1]}\x15${toks[2]}`,
    };
  }
  
  // If that fails, try the old format parsing
  if (postResponse.length > 9) {
    const dissectedString = postResponse.substring(4, postResponse.length - 5);
    const oldToks = dissectedString.split('^');
    
    if (oldToks.length >= 15) {
      console.log('✅ Successfully parsed session codes using legacy format');
      return {
        dwd: oldToks[0],
        wfaacl: oldToks[3],
        encses: oldToks[14],
        'User-Type': oldToks[6],
        sessionid: `${oldToks[1]}\x15${oldToks[2]}`,
      };
    }
  }
  
  // If both parsing methods fail, check for specific error messages
  const rootText = (cleanResponse || postResponse || '').toLowerCase();
  
  // Only throw for explicit authentication errors
  if (rootText.includes('invalid username or password') || 
      rootText.includes('invalid user') || 
      rootText.includes('invalid login') ||
      rootText.includes('locked account') ||
      rootText.includes('login failed')) {
    throw new Error('Invalid username or password, or account is locked');
  }
  
  // For other parsing failures, log but don't necessarily throw
  console.warn('⚠️ Session code parsing failed, response text:', rootText.substring(0, 200));
  console.warn('⚠️ Response length:', postResponse.length, 'Token count:', toks.length);
  
  // Return null to indicate parsing failed, but let caller decide how to handle
  return null;
}
