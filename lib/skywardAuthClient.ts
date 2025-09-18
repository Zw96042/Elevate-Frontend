// This file contains the Skyward AUTH logic migrated from the backend to the frontend.
// It is designed for use in a React Native/Expo environment.
// Node.js-specific code has been removed or replaced.


import axios from 'axios';
import { parse } from 'node-html-parser';
import { logger } from './core/Logger';

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
export async function getNewSessionCodes({ username, password, baseURL }: SkywardLoginParams): Promise<SkywardSessionCodes | null> {
  logger.info('Auth API: Starting authentication request', { 
    username: username?.substring(0, 3) + '***', // Log partial username for debugging
    baseURL,
    hasPassword: !!password 
  });
  
  if (!baseURL || typeof baseURL !== 'string') {
    logger.error('Auth API: Invalid baseURL provided', undefined, { providedBaseURL: baseURL });
    throw new Error('Invalid baseURL provided');
  }
  const cleanBaseURL = baseURL.endsWith('/') ? baseURL : baseURL + '/';
  const authenticationURL = cleanBaseURL + 'skyporthttp.w';
  
  logger.info('Auth API: Constructed authentication URL', { authenticationURL });
  
  try {
    new URL(authenticationURL);
  } catch (error) {
    logger.error('Auth API: Invalid authentication URL', error as Error, { authenticationURL });
    throw new Error(`Invalid authentication URL: ${authenticationURL}`);
  }
  const formData = new URLSearchParams({
    codeType: 'tryLogin',
    login: username,
    password: password,
    requestAction: 'eel',
  });
  
  logger.info('Auth API: Sending POST request to Skyward', { 
    url: authenticationURL,
    formDataKeys: Array.from(formData.keys())
  });
  
  try {
    const response = await axios.post(authenticationURL, formData.toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });
    
    logger.info('Auth API: Received response from Skyward', { 
      status: response.status,
      statusText: response.statusText,
      responseLength: response.data?.length || 0,
      responsePreview: response.data?.substring(0, 100) + '...' // First 100 chars
    });
    
    const parsed = parsePostResponse(response.data);
    if (!parsed) {
      logger.warn('Auth API: Failed to parse response data', {
        responseData: response.data?.substring(0, 500) // Log more of the response for debugging
      });
      return null; // Return null instead of throwing to avoid stack traces
    }
    
    logger.info('Auth API: Successfully parsed session codes', {
      hasDwd: !!parsed.dwd,
      hasWfaacl: !!parsed.wfaacl,
      hasEncses: !!parsed.encses,
      userType: parsed['User-Type'],
      hasSessionId: !!parsed.sessionid
    });
    
    return parsed;
  } catch (error: any) {
    logger.error('Auth API: Request failed with error', error, { 
      code: error.code,
      status: error.response?.status,
      statusText: error.response?.statusText,
      responseData: error.response?.data?.substring(0, 500)
    });
    // Don't throw errors that will create stack traces, just return null
    return null;
  }
}

/**
 * Parse login response string.
 * @param postResponse The raw response string from login.
 */
export function parsePostResponse(postResponse: string): SkywardSessionCodes | null {
  logger.info('Auth API: Parsing POST response', { 
    hasResponse: !!postResponse,
    responseLength: postResponse?.length || 0,
    responsePreview: postResponse?.substring(0, 100) + '...'
  });
  
  if (!postResponse) {
    logger.warn('Auth API: Empty response received');
    return null;
  }
  
  try {
    const dissectedString = postResponse.substring(4, postResponse.length - 5);
    const toks = dissectedString.split('^');
    
    logger.info('Auth API: Dissected response into tokens', { 
      dissectedLength: dissectedString.length,
      tokenCount: toks.length,
      tokensPreview: toks.slice(0, 5).map((t, i) => `[${i}]: ${t.substring(0, 20)}...`)
    });
    
    if (toks.length < 15) {
      logger.warn('Auth API: Insufficient tokens in response, checking for error messages', {
        tokenCount: toks.length,
        expectedMinimum: 15
      });
      
      const root = parse(postResponse);
      const rootText = (root.text || postResponse || '').toLowerCase();
      
      logger.info('Auth API: Parsed HTML response text', {
        rootTextLength: rootText.length,
        rootTextPreview: rootText.substring(0, 200)
      });
      
      if (rootText.includes('invalid username or password') || 
          rootText.includes('invalid user') || 
          rootText.includes('invalid login') ||
          rootText.includes('locked') ||
          rootText.includes('disabled')) {
        logger.warn('Auth API: Authentication failure detected in response', {
          detectedError: 'Invalid credentials or locked account'
        });
        // Return null instead of throwing for invalid credentials
        return null;
      }
      
      logger.warn('Auth API: Parsing failed - unknown response format', {
        tokenCount: toks.length,
        responsePreview: postResponse.substring(0, 300)
      });
      // Return null for other parsing failures too
      return null;
    }
    
    const sessionCodes = {
      dwd: toks[0],
      wfaacl: toks[3],
      encses: toks[14],
      'User-Type': toks[6],
      sessionid: `${toks[1]}\x15${toks[2]}`,
    };
    
    logger.info('Auth API: Successfully extracted session codes', {
      dwd: sessionCodes.dwd?.substring(0, 10) + '...',
      wfaacl: sessionCodes.wfaacl?.substring(0, 10) + '...',
      encses: sessionCodes.encses?.substring(0, 10) + '...',
      userType: sessionCodes['User-Type'],
      sessionIdLength: sessionCodes.sessionid?.length
    });
    
    return sessionCodes;
  } catch (error: any) {
    logger.error('Auth API: Exception during response parsing', error, {
      responseLength: postResponse?.length || 0,
      responsePreview: postResponse?.substring(0, 200)
    });
    // Always return null instead of throwing
    return null;
  }
}
