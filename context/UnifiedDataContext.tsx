import React, { createContext, useContext, useState, useCallback, useEffect } from 'react';
import { UnifiedDataManager, UnifiedCourseData } from '@/lib/unifiedDataManager';

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
	const [coursesData, setCoursesData] = useState<UnifiedCourseData[] | null>(null);
	const [loading, setLoading] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const [lastUpdated, setLastUpdated] = useState<string | null>(null);

	const refreshCourses = useCallback(async (force = false) => {
		console.log('🔄 UnifiedDataContext.refreshCourses called with force:', force);
		setLoading(true);
		setError(null);
		
		try {
			const result = await UnifiedDataManager.getCombinedData(force);
			if (result.success && result.courses) {
				setCoursesData(result.courses);
				setLastUpdated(result.lastUpdated || new Date().toISOString());
				console.log('✅ Courses data updated in context, count:', result.courses.length);
			} else {
				setCoursesData(null);
				setError(result.error || 'Failed to load courses');
				console.error('❌ Failed to load courses:', result.error);
			}
		} catch (error: any) {
			setCoursesData(null);
			setError(error.message || 'Unknown error occurred');
			console.error('❌ Error in refreshCourses:', error);
		} finally {
			setLoading(false);
		}
	}, []);

	const clearCache = useCallback(async () => {
		console.log('🗑️ UnifiedDataContext.clearCache called');
		try {
			await UnifiedDataManager.clearCache();
			// Reset local state
			setCoursesData(null);
			setLastUpdated(null);
			setError(null);
			console.log('✅ Cache cleared and local state reset');
		} catch (error: any) {
			console.error('❌ Error clearing cache:', error);
			setError(error.message || 'Failed to clear cache');
		}
	}, []);

	// Load initial data on mount
	useEffect(() => {
		refreshCourses(false); // Use cache if available
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
