import React, { createContext, useContext, useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { DataService, UnifiedCourseData } from '@/lib/services';
import { useSettingSheet } from '@/context/SettingSheetContext';
import { transformDataForShowoffMode, shouldEnableShowoffMode } from '@/utils/showoffMode';
import { DeviceEventEmitter } from 'react-native';
import { logger, Modules } from '@/lib/utils/logger';
import {
	getAccountDataGeneration,
	isLatestAccountRequest,
} from '@/lib/utils/account-data-cache';

interface UnifiedDataContextType {
	coursesData: UnifiedCourseData[] | null;
	setCoursesData: React.Dispatch<React.SetStateAction<UnifiedCourseData[] | null>>;
	loading: boolean;
	error: string | null;
	refreshCourses: (force?: boolean) => Promise<void>;
	clearCache: () => Promise<void>;
	lastUpdated: string | null;
}

const UnifiedDataContext = createContext<UnifiedDataContextType | undefined>(undefined);

export const UnifiedDataProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
	const [rawCoursesData, setRawCoursesData] = useState<UnifiedCourseData[] | null>(null);
	const [loading, setLoading] = useState(true); // Start as true since we load on mount
	const [error, setError] = useState<string | null>(null);
	const [lastUpdated, setLastUpdated] = useState<string | null>(null);
	const [hasInitialLoad, setHasInitialLoad] = useState(false); // Track if initial load happened
	const latestRefreshID = useRef(0);
	
	const { username, showoffMode } = useSettingSheet();

	// Apply showoff mode transformation if enabled
	const coursesData = useMemo(() => {
		if (showoffMode && shouldEnableShowoffMode(username)) {
			return transformDataForShowoffMode(rawCoursesData);
		}
		return rawCoursesData;
	}, [rawCoursesData, showoffMode, username]);

	const setCoursesData = useCallback((data: React.SetStateAction<UnifiedCourseData[] | null>) => {
		setRawCoursesData(data);
	}, []);

	const refreshCourses = useCallback(async (force = false) => {
		// Prevent multiple simultaneous refresh calls (but allow initial load)
		if (loading && !force && hasInitialLoad) {
			console.log('⏸️ [Context] Courses refresh already in progress, skipping...');
			return;
		}

		const requestID = ++latestRefreshID.current;
		const generation = getAccountDataGeneration();
		console.log('🔄 [Context] refreshCourses called with force:', force);
		setLoading(true);
		setHasInitialLoad(true);
		setError(null);
		
		try {
			const result = await DataService.getCombinedData(force);
			if (!isLatestAccountRequest(generation, requestID, latestRefreshID.current)) return;
			console.log('📦 [Context] DataService result:', { 
				success: result.success, 
				coursesCount: result.courses?.length || 0,
				error: result.error 
			});
			if (result.success && result.courses) {
				setRawCoursesData(result.courses);
				setLastUpdated(result.lastUpdated || new Date().toISOString());
				console.log('✅ [Context] Courses data updated, count:', result.courses.length);
			} else {
				const errorMessage = result.error || 'Failed to load courses';
				setError(errorMessage);
				console.error('❌ [Context] Failed to load courses:', result.error);
				
				// If it's an authentication error, don't retry automatically
				if (errorMessage.includes('Invalid username or password') || 
				    errorMessage.includes('Authentication failed') ||
				    errorMessage.includes('wait') && errorMessage.includes('seconds')) {
					console.log('🚫 [Context] Authentication error detected, stopping automatic retries');
				}
			}
		} catch (error: any) {
			if (!isLatestAccountRequest(generation, requestID, latestRefreshID.current)) return;
			const errorMessage = error.message || 'Unknown error occurred';
			setError(errorMessage);
			logger.error(Modules.DATA, 'Course refresh failed', error);
		} finally {
			if (requestID === latestRefreshID.current) {
				console.log('🏁 [Context] Setting loading to false');
				setLoading(false);
			}
		}
	}, [loading, hasInitialLoad]);

	const clearCache = useCallback(async () => {
		console.log('🗑️ UnifiedDataContext.clearCache called');
		try {
			latestRefreshID.current += 1;
			await DataService.clearCache();
			// Reset local state
			setRawCoursesData(null);
			setLastUpdated(null);
			setError(null);
			setLoading(false);
			console.log('✅ Cache cleared and local state reset');
		} catch (error: any) {
			logger.error(Modules.DATA, 'Error clearing cache', error);
			setError(error.message || 'Failed to clear cache');
			setLoading(false);
		}
	}, []);

	// Load initial data on mount (only once)
	useEffect(() => {
		console.log('🚀 [Context] Initial load useEffect triggered', { 
			hasData: !!rawCoursesData, 
			loading, 
			error 
		});
		// Always try to load on mount since we start with loading: true
		refreshCourses(false); // Use cache if available
	}, []); // Empty deps - only run once on mount

	useEffect(() => {
		const invalid = DeviceEventEmitter.addListener('credentialsInvalid', () => {
			latestRefreshID.current += 1;
			setRawCoursesData(null);
			setLastUpdated(null);
			setError(null);
			setLoading(false);
		});
		const added = DeviceEventEmitter.addListener('credentialsAdded', () => {
			void refreshCourses(true);
		});

		return () => {
			invalid.remove();
			added.remove();
		};
	}, [refreshCourses]);

	return (
		<UnifiedDataContext.Provider value={{ 
			coursesData, 
			setCoursesData, 
			loading, 
			error, 
			refreshCourses, 
			clearCache,
			lastUpdated 
		}}>
			{children}
		</UnifiedDataContext.Provider>
	);
};

export const useUnifiedData = () => {
	const context = useContext(UnifiedDataContext);
	if (!context) {
		throw new Error('useUnifiedData must be used within a UnifiedDataProvider');
	}
	return context;
};
