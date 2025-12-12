// Centralized logging system with levels and formatting

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  NONE = 4,
}

class Logger {
  private currentLevel: LogLevel = __DEV__ ? LogLevel.DEBUG : LogLevel.WARN;
  private enabledModules: Set<string> = new Set();
  private disabledModules: Set<string> = new Set();

  /**
   * Set the global log level
   */
  setLevel(level: LogLevel) {
    this.currentLevel = level;
  }

  /**
   * Enable logging for specific modules
   */
  enableModule(...modules: string[]) {
    modules.forEach(m => this.enabledModules.add(m));
  }

  /**
   * Disable logging for specific modules
   */
  disableModule(...modules: string[]) {
    modules.forEach(m => this.disabledModules.add(m));
  }

  /**
   * Check if a module should log
   */
  private shouldLog(module: string, level: LogLevel): boolean {
    if (level < this.currentLevel) return false;
    if (this.disabledModules.has(module)) return false;
    if (this.enabledModules.size > 0 && !this.enabledModules.has(module)) return false;
    return true;
  }

  /**
   * Format log message with emoji and module
   */
  private format(emoji: string, module: string, message: string, data?: any): string {
    const timestamp = new Date().toLocaleTimeString();
    const prefix = `${emoji} [${module}]`;
    return data ? `${prefix} ${message}` : `${prefix} ${message}`;
  }

  /**
   * Debug level - detailed information for debugging
   */
  debug(module: string, message: string, data?: any) {
    if (!this.shouldLog(module, LogLevel.DEBUG)) return;
    const formatted = this.format('🔍', module, message, data);
    if (data) {
      console.log(formatted, data);
    } else {
      console.log(formatted);
    }
  }

  /**
   * Info level - general information
   */
  info(module: string, message: string, data?: any) {
    if (!this.shouldLog(module, LogLevel.INFO)) return;
    const formatted = this.format('ℹ️', module, message, data);
    if (data) {
      console.log(formatted, data);
    } else {
      console.log(formatted);
    }
  }

  /**
   * Success level - successful operations
   */
  success(module: string, message: string, data?: any) {
    if (!this.shouldLog(module, LogLevel.INFO)) return;
    const formatted = this.format('✅', module, message, data);
    if (data) {
      console.log(formatted, data);
    } else {
      console.log(formatted);
    }
  }

  /**
   * Warn level - warnings
   */
  warn(module: string, message: string, data?: any) {
    if (!this.shouldLog(module, LogLevel.WARN)) return;
    const formatted = this.format('⚠️', module, message, data);
    if (data) {
      console.warn(formatted, data);
    } else {
      console.warn(formatted);
    }
  }

  /**
   * Error level - errors
   */
  error(module: string, message: string, error?: any) {
    if (!this.shouldLog(module, LogLevel.ERROR)) return;
    const formatted = this.format('❌', module, message);
    if (error) {
      console.error(formatted, error);
    } else {
      console.error(formatted);
    }
  }

  /**
   * API call logging
   */
  api(module: string, method: string, endpoint: string, status?: 'start' | 'success' | 'error', duration?: number) {
    if (!this.shouldLog(module, LogLevel.INFO)) return;
    
    if (status === 'start') {
      console.log(`🌐 [${module}] ${method} ${endpoint}`);
    } else if (status === 'success') {
      console.log(`✅ [${module}] ${method} ${endpoint} (${duration}ms)`);
    } else if (status === 'error') {
      console.error(`❌ [${module}] ${method} ${endpoint} failed (${duration}ms)`);
    }
  }

  /**
   * Cache logging
   */
  cache(module: string, action: 'hit' | 'miss' | 'set' | 'clear', key?: string, age?: number) {
    if (!this.shouldLog(module, LogLevel.DEBUG)) return;
    
    if (action === 'hit') {
      console.log(`⚡ [${module}] Cache HIT${key ? `: ${key}` : ''}${age ? ` (${Math.round(age / 1000)}s old)` : ''}`);
    } else if (action === 'miss') {
      console.log(`📦 [${module}] Cache MISS${key ? `: ${key}` : ''}`);
    } else if (action === 'set') {
      console.log(`💾 [${module}] Cache SET${key ? `: ${key}` : ''}`);
    } else if (action === 'clear') {
      console.log(`🗑️ [${module}] Cache CLEAR${key ? `: ${key}` : ''}`);
    }
  }

  /**
   * Performance timing
   */
  time(module: string, label: string): () => void {
    if (!this.shouldLog(module, LogLevel.DEBUG)) return () => {};
    
    const start = Date.now();
    return () => {
      const duration = Date.now() - start;
      console.log(`⏱️ [${module}] ${label}: ${duration}ms`);
    };
  }

  /**
   * Group related logs
   */
  group(module: string, label: string, collapsed: boolean = false) {
    if (!this.shouldLog(module, LogLevel.DEBUG)) return;
    
    if (collapsed) {
      console.groupCollapsed(`📂 [${module}] ${label}`);
    } else {
      console.group(`📂 [${module}] ${label}`);
    }
  }

  groupEnd() {
    console.groupEnd();
  }
}

// Export singleton instance
export const logger = new Logger();

// Module constants for consistency
export const Modules = {
  // Services
  AUTH: 'AuthService',
  DATA: 'DataService',
  MESSAGE: 'MessageService',
  
  // API
  API_AUTH: 'API:Auth',
  API_GRADES: 'API:Grades',
  API_MESSAGES: 'API:Messages',
  API_HISTORY: 'API:History',
  
  // Pages
  PAGE_CLASS: 'Page:Class',
  PAGE_INBOX: 'Page:Inbox',
  PAGE_HOME: 'Page:Home',
  PAGE_GPA: 'Page:GPA',
  
  // Utils
  SESSION: 'SessionManager',
  DEDUP: 'RequestDedup',
  CACHE: 'Cache',
} as const;

// Convenience exports for common patterns
export const log = {
  // Service logs
  service: {
    start: (module: string, operation: string) => 
      logger.info(module, `Starting ${operation}`),
    success: (module: string, operation: string, duration?: number) => 
      logger.success(module, `${operation} completed${duration ? ` (${duration}ms)` : ''}`),
    error: (module: string, operation: string, error: any) => 
      logger.error(module, `${operation} failed`, error),
  },
  
  // API logs
  api: {
    request: (module: string, endpoint: string) => 
      logger.api(module, 'POST', endpoint, 'start'),
    success: (module: string, endpoint: string, duration: number) => 
      logger.api(module, 'POST', endpoint, 'success', duration),
    error: (module: string, endpoint: string, duration: number, error: any) => {
      logger.api(module, 'POST', endpoint, 'error', duration);
      logger.error(module, 'Request failed', error);
    },
  },
  
  // Cache logs
  cache: {
    hit: (module: string, key?: string, age?: number) => 
      logger.cache(module, 'hit', key, age),
    miss: (module: string, key?: string) => 
      logger.cache(module, 'miss', key),
    set: (module: string, key?: string) => 
      logger.cache(module, 'set', key),
    clear: (module: string, key?: string) => 
      logger.cache(module, 'clear', key),
  },
};

// Example usage:
// import { logger, Modules, log } from '@/lib/utils/logger';
//
// // Simple logging
// logger.info(Modules.AUTH, 'User authenticated');
// logger.error(Modules.DATA, 'Failed to fetch', error);
//
// // Cache logging
// log.cache.hit(Modules.DATA, 'gradeInfo_123');
//
// // API logging
// log.api.request(Modules.API_GRADES, '/grades');
// log.api.success(Modules.API_GRADES, '/grades', 250);
//
// // Performance timing
// const endTimer = logger.time(Modules.DATA, 'fetchGrades');
// // ... do work ...
// endTimer(); // Logs: ⏱️ [DataService] fetchGrades: 250ms
//
// // Grouped logs
// logger.group(Modules.DATA, 'Processing grades');
// logger.debug(Modules.DATA, 'Step 1');
// logger.debug(Modules.DATA, 'Step 2');
// logger.groupEnd();
