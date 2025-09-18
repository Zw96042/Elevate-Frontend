/**
 * Unified API Client
 * Centralized API handling with error management, retry logic, and standardized responses
 */

import { CredentialManager } from './CredentialManager';
import { CacheManager } from './CacheManager';
import { createComponentLogger } from './Logger';
import { ApiResponse, ApiError, ErrorWithDetails, SkywardSessionCodes } from '@/interfaces/interfaces';
import AsyncStorage from '@react-native-async-storage/async-storage';

const config = require('../development.config.js');
const logger = createComponentLogger('ApiClient');

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  headers?: Record<string, string>;
  body?: any;
  timeout?: number;
  retries?: number;
  useCache?: boolean;
  cacheTTL?: number;
  cacheKey?: string;
}

export class ApiClient {
  private static readonly DEFAULT_TIMEOUT = 30000; // 30 seconds
  private static readonly DEFAULT_RETRIES = 1; // Reduced from 3 to 1 to minimize log noise
  private static readonly RETRY_DELAY = 1000; // 1 second

  /**
   * Make an authenticated request to the backend
   */
  static async request<T = any>(
    endpoint: string,
    options: RequestOptions = {}
  ): Promise<ApiResponse<T>> {
    const {
      method = 'POST',
      headers = {},
      body,
      timeout = this.DEFAULT_TIMEOUT,
      retries = this.DEFAULT_RETRIES,
      useCache = false,
      cacheTTL,
      cacheKey,
    } = options;

    // Check cache first if enabled
    if (useCache && cacheKey) {
      const cachedData = await CacheManager.get<ApiResponse<T>>(cacheKey);
      if (cachedData) {
        logger.debug('Cache hit for request', { 
          method: 'request',
          endpoint,
          cacheKey 
        });
        return cachedData;
      }
      logger.debug('Cache miss for request', { 
        method: 'request',
        endpoint,
        cacheKey 
      });
    }

    const startTime = Date.now();
    logger.info(`Starting ${method} request to ${endpoint}`, {
      method: 'request',
      endpoint,
      requestMethod: method,
      useCache,
      retries
    });

    let lastError: Error | null = null;
    let hasAttemptedReauth = false;

    for (let attempt = 0; attempt <= retries; attempt++) {
      try {
        if (attempt > 0) {
          logger.warn(`Retry attempt ${attempt} for ${endpoint}`, {
            method: 'request',
            endpoint,
            attempt
          });
        }

        logger.info('🚀 HEAVY LOGGING: Making API request attempt', {
          method: 'request',
          endpoint,
          attempt: attempt + 1,
          maxRetries: retries,
          requestMethod: method,
          hasHeaders: Object.keys(headers).length > 0,
          hasBody: !!body,
          useCache,
          cacheKey,
          timeout,
          timestamp: new Date().toISOString()
        });

        const response = await this.makeRequest<T>(endpoint, {
          method,
          headers,
          body,
          timeout,
        });

        const duration = Date.now() - startTime;
        logger.info(`🎉 HEAVY LOGGING: Request completed successfully`, {
          method: 'request',
          endpoint,
          duration,
          success: response.success,
          attempt: attempt + 1,
          responseDataSize: response.data ? JSON.stringify(response.data).length : 0,
          responseKeys: response.data && typeof response.data === 'object' ? Object.keys(response.data) : 'not-object'
        });

        // Cache successful responses if enabled
        if (useCache && cacheKey && response.success) {
          await CacheManager.set(cacheKey, response, cacheTTL);
          logger.debug('📦 HEAVY LOGGING: Response cached', {
            method: 'request',
            cacheKey,
            cacheTTL
          });
        }

        return response;
      } catch (error) {
        lastError = error as Error;
        
        logger.error(`💥 HEAVY LOGGING: Request attempt ${attempt + 1} failed`, lastError, {
          method: 'request',
          endpoint,
          attempt: attempt + 1,
          maxRetries: retries
        });
        
        // Handle session expiration with automatic re-authentication
        if (this.isAuthError(error) && !hasAttemptedReauth) {
          logger.warn('Session expired, attempting automatic re-authentication', {
            method: 'request',
            endpoint
          });
          
          try {
            // Import authenticate function dynamically to avoid circular imports
            const { authenticate } = await import('../authHandler');
            const authResult = await authenticate();
            
            if (authResult.success) {
              logger.info('Re-authentication successful, retrying request', {
                method: 'request',
                endpoint
              });
              hasAttemptedReauth = true;
              // Reset the attempt counter to give the request a fresh try with new auth
              attempt = -1; // Will be incremented to 0 in next iteration
              continue;
            } else {
              logger.error('Re-authentication failed', undefined, {
                method: 'request',
                endpoint,
                authError: authResult.error
              });
              // Don't retry further, return generic error
              break;
            }
          } catch (authError) {
            logger.error('Re-authentication attempt failed', authError as Error, {
              method: 'request',
              endpoint
            });
            // Don't retry further, return generic error
            break;
          }
        }

        // Don't retry on authentication errors if we already tried re-auth
        if (this.isAuthError(error)) {
          logger.warn('Authentication error after re-auth attempt, not retrying', {
            method: 'request',
            endpoint
          });
          break;
        }

        // Don't retry on the last attempt
        if (attempt === retries) {
          break;
        }

        // Wait before retrying
        const delay = this.RETRY_DELAY * (attempt + 1);
        logger.debug(`Waiting ${delay}ms before retry`, {
          method: 'request',
          delay
        });
        await this.delay(delay);
      }
    }

    const totalDuration = Date.now() - startTime;
    
    // Return generic error message for auth failures, specific errors for others
    if (this.isAuthError(lastError)) {
      logger.error(`Authentication failed after re-auth attempt`, lastError || undefined, {
        method: 'request',
        endpoint,
        totalDuration,
        attempts: retries + 1
      });
      
      return {
        success: false,
        error: 'Unable to authenticate. Please check your credentials and try again.',
      };
    }
    
    logger.error(`Request failed after all attempts`, lastError || undefined, {
      method: 'request',
      endpoint,
      totalDuration,
      attempts: retries + 1
    });

    return {
      success: false,
      error: 'Network error. Please check your connection and try again.',
    };
  }

  /**
   * Make the actual HTTP request
   */
  private static async makeRequest<T>(
    endpoint: string,
    options: {
      method: string;
      headers: Record<string, string>;
      body?: any;
      timeout: number;
    }
  ): Promise<ApiResponse<T>> {
    const { method, headers, body, timeout } = options;

    logger.debug('Preparing HTTP request', {
      method: 'makeRequest',
      endpoint,
      requestMethod: method,
      timeout,
      hasBody: !!body
    });

    // Get session codes
    const sessionCodes = await CredentialManager.getSessionCodes();
    const baseUrl = await CredentialManager.getBaseUrl();

    logger.info('🔐 HEAVY LOGGING: Retrieved authentication credentials', {
      method: 'makeRequest',
      hasSessionCodes: !!sessionCodes,
      hasBaseUrl: !!baseUrl,
      baseUrl,
      sessionCodesKeys: sessionCodes ? Object.keys(sessionCodes) : null,
      sessionCodesPreview: sessionCodes ? {
        hasDwd: !!sessionCodes.dwd,
        hasWfaacl: !!sessionCodes.wfaacl,
        hasEncses: !!sessionCodes.encses,
        hasUserType: !!sessionCodes['User-Type'],
        hasSessionId: !!sessionCodes.sessionid,
        dwdLength: sessionCodes.dwd?.length,
        sessionIdLength: sessionCodes.sessionid?.length
      } : null
    });

    if (!sessionCodes || !baseUrl) {
      logger.error('💥 HEAVY LOGGING: Missing authentication credentials', undefined, {
        method: 'makeRequest',
        hasSessionCodes: !!sessionCodes,
        hasBaseUrl: !!baseUrl,
        baseUrl
      });
      throw new Error('Missing authentication credentials');
    }

    // Handle development mode
    if (this.isDevMode(sessionCodes)) {
      logger.info('Using development mode', {
        method: 'makeRequest',
        endpoint
      });
      return this.handleDevMode<T>(endpoint);
    }

    // Prepare request
    const url = `${config.BACKEND_IP}${endpoint}`;
    const requestBody = this.prepareRequestBody(body, sessionCodes, baseUrl);

    logger.info('🔧 HEAVY LOGGING: Request configuration', {
      method: 'makeRequest',
      configBackendIP: config.BACKEND_IP,
      configApiUrl: config.apiUrl,
      endpoint,
      finalUrl: url,
      requestBodyKeys: requestBody ? Object.keys(requestBody) : null,
      requestBodySize: requestBody ? JSON.stringify(requestBody).length : 0,
      requestBodyPreview: requestBody ? JSON.stringify(requestBody).substring(0, 200) + '...' : null
    });

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    const requestStart = Date.now();
    
    logger.info('🚀 HEAVY LOGGING: Making HTTP request', {
      method: 'makeRequest',
      url,
      httpMethod: method,
      headers: Object.keys(headers),
      hasBody: !!requestBody,
      bodySize: requestBody ? JSON.stringify(requestBody).length : 0,
      timeout,
      timestamp: new Date().toISOString()
    });

    try {
    logger.info('🌐 HEAVY LOGGING: Calling fetch()', {
      method: 'makeRequest',
      fetchUrl: url,
      fetchOptions: {
        method,
        hasHeaders: Object.keys(headers).length > 0,
        hasBody: !!requestBody,
        hasSignal: !!controller.signal
      },
      networkInfo: {
        userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : 'unknown',
        onLine: typeof navigator !== 'undefined' ? navigator.onLine : 'unknown',
        connection: typeof navigator !== 'undefined' && 'connection' in navigator ? 
          (navigator as any).connection?.effectiveType : 'unknown'
      },
      connectivityTest: {
        message: 'About to test basic connectivity to backend server',
        testUrl: config.BACKEND_IP
      }
    });

    // Add a basic connectivity test
    try {
      logger.info('🔍 HEAVY LOGGING: Testing basic connectivity', {
        method: 'makeRequest',
        testUrl: config.BACKEND_IP + '/health'
      });
      
      // First test: Can we reach any external server?
      try {
        const externalTestController = new AbortController();
        const externalTimeout = setTimeout(() => externalTestController.abort(), 3000);
        
        const externalTest = await fetch('https://httpbin.org/get', {
          method: 'GET',
          signal: externalTestController.signal
        });
        
        clearTimeout(externalTimeout);
        logger.info('🌍 HEAVY LOGGING: External connectivity test passed', {
          method: 'makeRequest',
          externalStatus: externalTest.status,
          message: 'Internet connection is working'
        });
      } catch (externalError) {
        logger.error('🌍 HEAVY LOGGING: External connectivity test failed', externalError as Error, {
          method: 'makeRequest',
          message: 'No internet connection or fetch is broken'
        });
      }
      
      // Second test: Can we reach our backend server?
      const connectivityTestController = new AbortController();
      const connectivityTimeout = setTimeout(() => connectivityTestController.abort(), 5000);
      
      const connectivityTest = await fetch(config.BACKEND_IP + '/health', {
        method: 'GET',
        signal: connectivityTestController.signal
      }).catch(e => {
        clearTimeout(connectivityTimeout);
        logger.warn('⚠️ HEAVY LOGGING: Backend connectivity test failed', {
          method: 'makeRequest',
          error: e.message,
          backendUrl: config.BACKEND_IP,
          suggestion: 'Backend server may be unreachable'
        });
        return null;
      });

      clearTimeout(connectivityTimeout);
      if (connectivityTest) {
        logger.info('✅ HEAVY LOGGING: Backend connectivity test passed', {
          method: 'makeRequest',
          status: connectivityTest.status,
          statusText: connectivityTest.statusText
        });
      }
    } catch (connectError) {
      logger.warn('⚠️ HEAVY LOGGING: Connectivity test error', {
        method: 'makeRequest',
        error: (connectError as Error).message
      });
    }
    
    // Prepare final fetch options
    const fetchOptions = {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
      body: requestBody ? JSON.stringify(requestBody) : undefined,
      // signal: controller.signal, // TEMPORARILY DISABLED FOR DEBUGGING
    };
    
    // FINAL DEBUG LOGGING RIGHT BEFORE FETCH
    console.log("FINAL FETCH URL:", url);
    console.log("FINAL FETCH BODY:", JSON.stringify(requestBody));
    console.log('🔥 FETCH OPTIONS METHOD:', fetchOptions.method);
    console.log('🔥 FETCH OPTIONS HEADERS:', fetchOptions.headers);
    console.log('🔥 FETCH OPTIONS BODY LENGTH:', fetchOptions.body ? fetchOptions.body.length : 'no body');
    console.log('🔥 ABORT CONTROLLER DISABLED FOR DEBUGGING');
    
    // Now make the actual request
    const response = await fetch(url, fetchOptions);

      // IMMEDIATELY LOG THE RAW RESPONSE - NO FLUFF
      console.log('🔥 RAW RESPONSE STATUS:', response.status);
      console.log('🔥 RAW RESPONSE OK:', response.ok);
      console.log('🔥 RAW RESPONSE HEADERS:', Object.fromEntries(response.headers.entries()));
      
      clearTimeout(timeoutId);
      const requestDuration = Date.now() - requestStart;

      logger.info('✅ HEAVY LOGGING: Fetch response received', {
        method: 'makeRequest',
        status: response.status,
        statusText: response.statusText,
        duration: requestDuration,
        ok: response.ok,
        responseType: response.type,
        responseUrl: response.url,
        responseHeaders: Object.fromEntries(response.headers.entries()),
        contentLength: response.headers.get('content-length'),
        contentType: response.headers.get('content-type')
      });

      if (!response.ok) {
        // Try to get error response body for debugging
        const errorText = await response.text();
        logger.error('❌ HEAVY LOGGING: HTTP response not ok - FULL ERROR RESPONSE', undefined, {
          method: 'makeRequest',
          status: response.status,
          statusText: response.statusText,
          responseHeaders: Object.fromEntries(response.headers.entries()),
          errorResponseBody: errorText,
          errorResponseLength: errorText.length
        });
        throw await this.createErrorFromResponse(response);
      }

      logger.info('📊 HEAVY LOGGING: Parsing response JSON', {
        method: 'makeRequest',
        contentType: response.headers.get('content-type'),
        responseSize: response.headers.get('content-length') || 'unknown'
      });

      // First get the raw text to log what we actually received
      const responseText = await response.text();
      
      // IMMEDIATELY LOG THE RAW RESPONSE BODY - NO FLUFF
      console.log('🔥 RAW RESPONSE BODY LENGTH:', responseText.length);
      console.log('🔥 RAW RESPONSE BODY:', responseText);
      console.log('🔥 RAW RESPONSE CONTENT-TYPE:', response.headers.get('content-type'));
      
      let data;
      try {
        data = JSON.parse(responseText);
        
        // IMMEDIATELY LOG THE PARSED DATA - NO FLUFF
        console.log('🔥 PARSED DATA TYPE:', typeof data);
        console.log('🔥 PARSED DATA:', data);
        
      } catch (parseError) {
        console.log('🔥 JSON PARSE ERROR:', (parseError as Error).message);
        console.log('🔥 FAILED TO PARSE THIS TEXT:', responseText);
        throw new Error(`Invalid JSON response: ${(parseError as Error).message}`);
      }
      
      console.log('🔥 REQUEST SUCCESS - RETURNING DATA:', data);
      
      return {
        success: true,
        data,
      };
    } catch (error) {
      clearTimeout(timeoutId);
      const requestDuration = Date.now() - requestStart;
      
      // Try to get more details about the network error
      let errorDetails: any = {
        errorName: (error as Error)?.name,
        errorMessage: (error as Error)?.message,
        errorStack: (error as Error)?.stack?.substring(0, 500),
        requestDetails: {
          method,
          headers: Object.keys(headers),
          hasBody: !!requestBody,
          timeout,
          url
        }
      };

      // Check if it's a fetch-specific error
      if (error instanceof TypeError && error.message === 'Network request failed') {
        errorDetails.networkDiagnostics = {
          possibleCauses: [
            'Backend server not running on ' + url,
            'CORS policy blocking request from React Native',
            'HTTP request to HTTPS app (mixed content)',
            'iOS App Transport Security blocking HTTP',
            'Network connectivity issue',
            'Firewall or proxy blocking request',
            'Invalid URL format'
          ],
          troubleshooting: {
            backendUrl: url,
            isHttp: url.startsWith('http://'),
            isHttps: url.startsWith('https://'),
            suggestion: url.startsWith('http://') ? 
              'Try HTTPS or configure ATS settings for HTTP' : 
              'Check backend server status'
          },
          nextSteps: [
            '1. Verify backend server is running',
            '2. Test URL in browser: ' + url,
            '3. Check app.json for HTTP security settings',
            '4. Try HTTPS instead of HTTP'
          ]
        };
      }

      // Try to get response details if available
      if ('response' in (error as any)) {
        const errorResponse = (error as any).response;
        if (errorResponse) {
          try {
            const errorText = await errorResponse.text();
            errorDetails.responseText = errorText.substring(0, 500);
            errorDetails.responseStatus = errorResponse.status;
            errorDetails.responseHeaders = Object.fromEntries(errorResponse.headers.entries());
          } catch (e) {
            errorDetails.responseReadError = 'Could not read error response';
          }
        }
      }
      
      logger.error('💥 HEAVY LOGGING: HTTP request failed with exception', error as Error, {
        method: 'makeRequest',
        duration: requestDuration,
        ...errorDetails
      });
      
      if (error instanceof Error && error.name === 'AbortError') {
        logger.error('⏰ HEAVY LOGGING: Request timed out', undefined, {
          method: 'makeRequest',
          timeout,
          duration: requestDuration
        });
        throw new Error('Request timeout');
      }
      
      throw error;
    }
  }

  /**
   * Test the working pattern from academicHistoryClient
   */
  private static async testWorkingPattern(): Promise<void> {
    logger.info('🧪 TESTING WORKING PATTERN: Starting test using academicHistoryClient approach');
    
    try {
      // Use the exact same pattern as academicHistoryClient
      const sessionCode = await AsyncStorage.getItem('sessionCode');
      logger.info('🧪 TESTING WORKING PATTERN: Got session code', { sessionCode: sessionCode ? 'present' : 'missing' });

      if (!sessionCode) {
        logger.warn('🧪 TESTING WORKING PATTERN: No session code found');
        return;
      }

      const url = `${config.BACKEND_IP}/scrape-report`;
      logger.info('🧪 TESTING WORKING PATTERN: Making direct fetch request', { url });
      console.log('🔥 WORKING PATTERN URL:', url);
      console.log('🔥 CONFIG BACKEND_IP:', config.BACKEND_IP);

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ sessionCode }),
      });

      logger.info('🧪 TESTING WORKING PATTERN: Got response', {
        status: response.status,
        statusText: response.statusText,
        ok: response.ok
      });

      const data = await response.json();
      console.log('🔥 WORKING PATTERN RAW RESPONSE:', data);

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(`🧪 TESTING WORKING PATTERN: Error occurred - ${errorMsg}`);
      console.log('🔥 WORKING PATTERN ERROR:', error);
    }
  }

  /**
   * Test basic connectivity with health endpoint
   */
  static async testHealthEndpoint(): Promise<void> {
    logger.info('🏥 HEALTH CHECK: Starting basic connectivity test');
    
    try {
      const url = `${config.BACKEND_IP}/health`;
      logger.info('🏥 HEALTH CHECK: Making request to health endpoint', { url });
      console.log('🔥 HEALTH ENDPOINT URL:', url);
      console.log('🔥 TESTING SIMPLE GOOGLE FIRST...');

      // First test a simple external API to confirm basic network works
      try {
        const googleTest = await fetch('https://httpbin.org/get', { method: 'GET' });
        console.log('🔥 GOOGLE TEST STATUS:', googleTest.status);
      } catch (googleError) {
        console.log('🔥 GOOGLE TEST FAILED:', googleError);
      }

      console.log('🔥 NOW TESTING YOUR BACKEND...');
      const response = await fetch(url, {
        method: 'GET', // FORCE GET METHOD FOR DEBUGGING
        headers: {
          'Content-Type': 'application/json',
        },
      });

      logger.info('🏥 HEALTH CHECK: Got response', {
        status: response.status,
        statusText: response.statusText,
        ok: response.ok
      });

      const data = await response.json();
      console.log('🔥 HEALTH RAW RESPONSE STATUS:', response.status);
      console.log('🔥 HEALTH RAW RESPONSE BODY:', data);

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(`🏥 HEALTH CHECK: Error occurred - ${errorMsg}`);
      console.log('🔥 HEALTH ERROR:', error);
      
      // Try localhost as fallback test
      console.log('🔥 TESTING LOCALHOST FALLBACK...');
      try {
        const localhostTest = await fetch('http://localhost:3000/health', {
          method: 'GET', // FORCE GET METHOD FOR DEBUGGING
          headers: { 'Content-Type': 'application/json' },
        });
        console.log('🔥 LOCALHOST TEST STATUS:', localhostTest.status);
      } catch (localhostError) {
        console.log('🔥 LOCALHOST TEST FAILED:', localhostError);
      }
    }
  }
  private static prepareRequestBody(
    body: any,
    sessionCodes: SkywardSessionCodes,
    baseUrl: string
  ): any {
    return {
      ...body,
      sessionid: sessionCodes.sessionid,
      encses: sessionCodes.encses,
      dwd: sessionCodes.dwd,
      wfaacl: sessionCodes.wfaacl,
      'User-Type': sessionCodes['User-Type'],
      baseUrl,
    };
  }

  /**
   * Handle development mode responses
   */
  private static async handleDevMode<T>(endpoint: string): Promise<ApiResponse<T>> {
    // Return mock data for development
    const mockData = await this.getMockData<T>(endpoint);
    return {
      success: true,
      data: mockData,
    };
  }

  /**
   * Get mock data for development
   */
  private static async getMockData<T>(endpoint: string): Promise<T> {
    // This would contain your existing dev data
    const mockResponses: Record<string, any> = {
      '/messages': [], // Your EMAILS mock data
      '/grades': {},
      '/academic-history': {},
    };

    return mockResponses[endpoint] || {} as T;
  }

  /**
   * Check if session codes are for development
   */
  private static isDevMode(sessionCodes: SkywardSessionCodes): boolean {
    return Object.values(sessionCodes).every(value => value === 'dev');
  }

  /**
   * Check if error is authentication related
   */
  private static isAuthError(error: any): boolean {
    return (
      error?.status === 401 ||
      error?.message?.includes('Session Expired') ||
      error?.message?.includes('Authentication failed')
    );
  }

  /**
   * Create error from HTTP response
   */
  private static async createErrorFromResponse(response: Response): Promise<ErrorWithDetails> {
    let message = `HTTP ${response.status}: ${response.statusText}`;
    let details: any = null;

    try {
      const errorData = await response.json();
      message = errorData.message || errorData.error || message;
      details = errorData;
    } catch {
      // Response is not JSON, use status text
    }

    if (response.status === 401) {
      // Handle session expiration
      await CredentialManager.setEmptySession(
        await CredentialManager.getBaseUrl() || ''
      );
      message = 'Session expired. Please log in again.';
    }

    const error = new Error(message) as ErrorWithDetails;
    error.status = response.status;
    error.details = details;
    
    return error;
  }

  /**
   * Delay utility for retries
   */
  private static delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Specific API methods
   */

  /**
   * Fetch messages
   */
  static async fetchMessages(useCache: boolean = true): Promise<ApiResponse> {
    return this.request('/messages', {
      useCache,
      cacheKey: CacheManager.KEYS.MESSAGES,
      cacheTTL: 2 * 60 * 1000, // 2 minutes
    });
  }

  /**
   * Fetch more messages
   */
  static async fetchMoreMessages(page: number): Promise<ApiResponse> {
    return this.request('/messages/more', {
      body: { page },
      useCache: true,
      cacheKey: `${CacheManager.KEYS.MESSAGES}_page_${page}`,
    });
  }

  /**
   * Fetch grade info
   */
  static async fetchGradeInfo(params: {
    corNumId: string;
    stuId: string;
    section: string;
    gbId: string;
  }): Promise<ApiResponse> {
    return this.request('/grade-info', {
      body: params,
      useCache: true,
      cacheKey: `${CacheManager.KEYS.GRADE_INFO}_${params.corNumId}_${params.stuId}`,
    });
  }

  /**
   * Fetch report card
   */
  static async fetchReportCard(useCache: boolean = true): Promise<ApiResponse> {
    logger.info('🚀 HEAVY LOGGING: Starting fetchReportCard', {
      method: 'fetchReportCard',
      useCache,
      cacheKey: CacheManager.KEYS.REPORT_CARD,
      cacheTTL: 5 * 60 * 1000,
      endpoint: '/scrape-report',
      timestamp: new Date().toISOString()
    });

    // TEST BASIC CONNECTIVITY FIRST
    await this.testHealthEndpoint();
    
    // TEST THE WORKING PATTERN
    await this.testWorkingPattern();

    const result = await this.request('/scrape-report', {
      useCache,
      cacheKey: CacheManager.KEYS.REPORT_CARD,
      cacheTTL: 5 * 60 * 1000, // 5 minutes
    });

    logger.info('📊 HEAVY LOGGING: fetchReportCard completed', {
      method: 'fetchReportCard',
      success: result.success,
      hasData: !!result.data,
      error: result.error,
      dataSize: result.data ? JSON.stringify(result.data).length : 0
    });

    return result;
  }

  /**
   * Fetch academic history
   */
  static async fetchAcademicHistory(useCache: boolean = true): Promise<ApiResponse> {
    return this.request('/academic-history', {
      useCache,
      cacheKey: CacheManager.KEYS.ACADEMIC_HISTORY,
      cacheTTL: 10 * 60 * 1000, // 10 minutes
    });
  }

  /**
   * Clear all caches
   */
  static async clearCache(): Promise<void> {
    await CacheManager.clear();
  }
}
