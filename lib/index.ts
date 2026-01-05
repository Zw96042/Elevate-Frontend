// Main library exports - clean, organized API
// This is the single entry point for all lib functionality

// Services - high-level business logic
export * from './services';

// API - low-level Skyward API calls
export * from './api';

// Types - TypeScript interfaces
export * from './types/api';

// Utils - helper functions
export { logger, Modules, log } from './utils/logger';
export { RequestDeduplicator } from './utils/request-deduplicator';
export { SessionManager } from './utils/session-manager';

// Legacy exports for backward compatibility
export { SkywardAuth } from './skywardAuthInfo';
export { UnifiedGPAManager, type GPAData, type UnifiedGPAResult } from './unifiedGpaManager';

// Re-export UnifiedCourseData from services for convenience
export type { UnifiedCourseData } from './services/data-service';
