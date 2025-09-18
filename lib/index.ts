/**
 * Core Library Exports
 * Centralized exports for all core functionality
 */

// Core systems
export { CredentialManager } from './core/CredentialManager';
export { CacheManager } from './core/CacheManager';
export { ApiClient } from './core/ApiClient';

// UI Components
export { BaseModal } from '../components/modals/BaseModal';
export { AssignmentModal, ConfirmationModal, LoadingModal } from '../components/modals/SpecializedModals';
export { GradeDisplay } from '../components/ui/GradeDisplay';
export { AssignmentList } from '../components/ui/AssignmentList';
export { TermSelector } from '../components/ui/TermSelector';
export { GradeStatistics } from '../components/ui/GradeStatistics';

// Types (re-export from interfaces)
export * from '../interfaces/interfaces';
