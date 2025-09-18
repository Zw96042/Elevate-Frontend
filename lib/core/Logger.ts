/**
 * Centralized logging utility for the frontend application
 * Provides structured logging with different levels and contexts
 */

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3
}

export interface LogContext {
  component?: string;
  method?: string;
  userId?: string;
  timestamp?: number;
  duration?: number | string;
  [key: string]: any;
}

// Global log level configuration
const CURRENT_LOG_LEVEL = __DEV__ ? LogLevel.DEBUG : LogLevel.WARN;

class Logger {
  private static instance: Logger;
  private logLevel: LogLevel = __DEV__ ? LogLevel.DEBUG : LogLevel.INFO;
  private enabledContexts: string[] = [];

  private constructor() {}

  static getInstance(): Logger {
    if (!Logger.instance) {
      Logger.instance = new Logger();
    }
    return Logger.instance;
  }

  setLogLevel(level: LogLevel): void {
    this.logLevel = level;
  }

  enableContext(context: string): void {
    if (!this.enabledContexts.includes(context)) {
      this.enabledContexts.push(context);
    }
  }

  disableContext(context: string): void {
    this.enabledContexts = this.enabledContexts.filter(c => c !== context);
  }

  private shouldLog(level: LogLevel, context?: string): boolean {
    if (level < this.logLevel) return false;
    if (context && this.enabledContexts.length > 0 && !this.enabledContexts.includes(context)) {
      return false;
    }
    return true;
  }

  private formatMessage(level: LogLevel, message: string, context?: LogContext): string {
    const timestamp = new Date().toISOString();
    const levelStr = LogLevel[level].padEnd(5);
    const componentStr = context?.component ? `[${context.component}]` : '';
    const methodStr = context?.method ? `.${context.method}()` : '';
    
    return `${timestamp} ${levelStr} ${componentStr}${methodStr} ${message}`;
  }

  private formatContext(context?: LogContext): string {
    if (!context) return '';
    
    const { component, method, timestamp, ...otherContext } = context;
    const contextEntries = Object.entries(otherContext);
    
    if (contextEntries.length === 0) return '';
    
    const contextStr = contextEntries
      .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
      .join(', ');
    
    return ` | Context: {${contextStr}}`;
  }

  debug(message: string, context?: LogContext): void {
    if (!this.shouldLog(LogLevel.DEBUG, context?.component)) return;
    if (LogLevel.DEBUG < CURRENT_LOG_LEVEL) return;
    
    const formattedMessage = this.formatMessage(LogLevel.DEBUG, message, context);
    const contextStr = this.formatContext(context);
    console.log(formattedMessage + contextStr);
  }

  info(message: string, context?: LogContext): void {
    if (!this.shouldLog(LogLevel.INFO, context?.component)) return;
    if (LogLevel.INFO < CURRENT_LOG_LEVEL) return;
    
    const formattedMessage = this.formatMessage(LogLevel.INFO, message, context);
    const contextStr = this.formatContext(context);
    console.info(formattedMessage + contextStr);
  }

  warn(message: string, context?: LogContext): void {
    if (!this.shouldLog(LogLevel.WARN, context?.component)) return;
    if (LogLevel.WARN < CURRENT_LOG_LEVEL) return;
    
    const formattedMessage = this.formatMessage(LogLevel.WARN, message, context);
    const contextStr = this.formatContext(context);
    console.warn(formattedMessage + contextStr);
  }

  error(message: string, error?: Error, context?: LogContext): void {
    if (!this.shouldLog(LogLevel.ERROR, context?.component)) return;
    
    // Completely suppress authentication-related errors to reduce noise
    if (message.includes('Authentication failed') || 
        message.includes('Skyward authentication failed') ||
        error?.message?.includes('Invalid user or pass') ||
        error?.message?.includes('authentication failed') ||
        error?.message?.includes('Failed to parse Skyward session codes')) {
      
      // Only log once per session for invalid credentials
      if (!this.hasLoggedAuthError) {
        console.warn('🔐 Authentication failed: Invalid credentials or server error (further auth errors suppressed)');
        this.hasLoggedAuthError = true;
      }
      return;
    }
    
    // Suppress network error spam when backend is down
    if ((message.includes('HTTP request failed') || 
         message.includes('Request attempt') || 
         message.includes('Request failed after all attempts') ||
         message.includes('External connectivity test failed') ||
         message.includes('Backend connectivity test failed') ||
         message.includes('Failed to fetch data from API') ||
         message.includes('💥 HEAVY LOGGING: Failed to fetch data from API')) && 
        (error?.message?.includes('Network request failed') || 
         error?.message?.includes('ECONNREFUSED') ||
         error?.message?.includes('Connection refused') ||
         error?.message?.includes('Aborted') ||
         error?.message?.includes('Network error'))) {
      
      // Only log network errors once per session
      if (!this.hasLoggedNetworkError) {
        console.warn('🌐 Backend server connection failed (network errors suppressed)');
        this.hasLoggedNetworkError = true;
      }
      return;
    }
    
    const formattedMessage = this.formatMessage(LogLevel.ERROR, message, context);
    const contextStr = this.formatContext(context);
    const errorStr = error ? ` | Error: ${error.message}` : '';
    
    // Log the error message without stack trace spam
    console.warn(formattedMessage + contextStr + errorStr);
    
    // NEVER show stack traces - they create noise and confusion
    // Stack traces are disabled in all environments to keep logs clean
  }

  private hasLoggedAuthError = false;
  private hasLoggedNetworkError = false;

  // Timing utilities
  startTimer(operation: string, context?: LogContext): () => void {
    const startTime = Date.now();
    this.debug(`Starting ${operation}`, { ...context, startTime });
    
    return () => {
      const duration = Date.now() - startTime;
      this.info(`Completed ${operation}`, { ...context, duration: `${duration}ms` });
    };
  }

  // API logging helpers
  logApiRequest(method: string, url: string, context?: LogContext): void {
    this.info(`API Request: ${method} ${url}`, {
      ...context,
      apiMethod: method,
      apiUrl: url
    });
  }

  logApiResponse(method: string, url: string, status: number, duration: number, context?: LogContext): void {
    const level = status >= 400 ? LogLevel.ERROR : status >= 300 ? LogLevel.WARN : LogLevel.INFO;
    const message = `API Response: ${method} ${url} - ${status}`;
    
    const logContext = {
      ...context,
      apiMethod: method,
      apiUrl: url,
      status,
      duration: `${duration}ms`
    };

    if (level === LogLevel.ERROR) {
      this.error(message, undefined, logContext);
    } else if (level === LogLevel.WARN) {
      this.warn(message, logContext);
    } else {
      this.info(message, logContext);
    }
  }

  // Authentication logging
  logAuthEvent(event: string, success: boolean, context?: LogContext): void {
    const message = `Auth ${event}: ${success ? 'SUCCESS' : 'FAILURE'}`;
    const level = success ? LogLevel.INFO : LogLevel.ERROR;
    
    if (level === LogLevel.ERROR) {
      this.error(message, undefined, { ...context, authEvent: event, success });
    } else {
      this.info(message, { ...context, authEvent: event, success });
    }
  }

  // Data operation logging
  logDataOperation(operation: string, dataType: string, count?: number, context?: LogContext): void {
    const countStr = count !== undefined ? ` (${count} items)` : '';
    this.info(`Data ${operation}: ${dataType}${countStr}`, {
      ...context,
      operation,
      dataType,
      count
    });
  }

  // Cache logging
  logCacheOperation(operation: 'hit' | 'miss' | 'set' | 'clear', key: string, context?: LogContext): void {
    this.debug(`Cache ${operation}: ${key}`, {
      ...context,
      cacheOperation: operation,
      cacheKey: key
    });
  }
}

// Export singleton instance
export const logger = Logger.getInstance();

// Component-specific logger factory
export function createComponentLogger(componentName: string) {
  return {
    debug: (message: string, context?: Omit<LogContext, 'component'>) => 
      logger.debug(message, { ...context, component: componentName }),
    info: (message: string, context?: Omit<LogContext, 'component'>) => 
      logger.info(message, { ...context, component: componentName }),
    warn: (message: string, context?: Omit<LogContext, 'component'>) => 
      logger.warn(message, { ...context, component: componentName }),
    error: (message: string, error?: Error, context?: Omit<LogContext, 'component'>) => 
      logger.error(message, error, { ...context, component: componentName }),
    startTimer: (operation: string, context?: Omit<LogContext, 'component'>) => 
      logger.startTimer(operation, { ...context, component: componentName })
  };
}
