import React, { createContext, useContext, useState, useCallback, useEffect, useMemo } from 'react';
import { DataService, UnifiedCourseData } from '@/lib/services';
import { useSettingSheet } from '@/context/SettingSheetContext';
import { transformDataForShowoffMode, shouldEnableShowoffMode } from '@/utils/showoffMode';

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
	const [loading, setLoading] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const [lastUpdated, setLastUpdated] = useState<string | null>(null);
	
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
		// Prevent multiple simultaneous refresh calls
		if (loading && !force) {
			console.log('⏸️ Courses refresh already in progress, skipping...');
			return;
		}

		console.log('🔄 UnifiedDataContext.refreshCourses called with force:', force);
		setLoading(true);
		setError(null);
		
		try {
			const result = await DataService.getCombinedData(force);
			if (result.success && result.courses) {
				setRawCoursesData(result.courses);
				setLastUpdated(result.lastUpdated || new Date().toISOString());
				console.log('✅ Courses data updated in context, count:', result.courses.length);
			} else {
				setRawCoursesData(null);
				const errorMessage = result.error || 'Failed to load courses';
				setError(errorMessage);
				console.error('❌ Failed to load courses:', result.error);
				
				// If it's an authentication error, don't retry automatically
				if (errorMessage.includes('Invalid username or password') || 
				    errorMessage.includes('Authentication failed') ||
				    errorMessage.includes('wait') && errorMessage.includes('seconds')) {
					console.log('🚫 Authentication error detected, stopping automatic retries');
				}
			}
		} catch (error: any) {
			setRawCoursesData(null);
			const errorMessage = error.message || 'Unknown error occurred';
			setError(errorMessage);
			console.error('❌ Error in refreshCourses:', error);
		} finally {
			setLoading(false);
		}
	}, [loading]);

	const clearCache = useCallback(async () => {
		console.log('🗑️ UnifiedDataContext.clearCache called');
		try {
			await DataService.clearCache();
			// Reset local state
			setRawCoursesData(null);
			setLastUpdated(null);
			setError(null);
			console.log('✅ Cache cleared and local state reset');
		} catch (error: any) {
			console.error('❌ Error clearing cache:', error);
			setError(error.message || 'Failed to clear cache');
		}
	}, []);

	// Load initial data on mount (only once)
	useEffect(() => {
		if (!rawCoursesData && !loading && !error) {
			refreshCourses(false); // Use cache if available
		}
	}, []); // Remove dependencies to prevent infinite loop

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
