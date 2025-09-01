import React, { createContext, useContext, useState, useCallback } from 'react';
import { UnifiedDataManager, UnifiedCourseData } from '@/lib/unifiedDataManager';

interface UnifiedDataContextType {
	coursesData: UnifiedCourseData[] | null;
	setCoursesData: React.Dispatch<React.SetStateAction<UnifiedCourseData[] | null>>;
	loading: boolean;
	error: string | null;
	refreshCourses: (force?: boolean) => Promise<void>;
}

const UnifiedDataContext = createContext<UnifiedDataContextType | undefined>(undefined);

export const UnifiedDataProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
	const [coursesData, setCoursesData] = useState<UnifiedCourseData[] | null>(null);
	const [loading, setLoading] = useState(false);
	const [error, setError] = useState<string | null>(null);

	const refreshCourses = useCallback(async (force = false) => {
		setLoading(true);
		setError(null);
		const result = await UnifiedDataManager.getCombinedData(force);
		if (result.success && result.courses) {
			setCoursesData(result.courses);
		} else {
			setCoursesData(null);
			setError(result.error || 'Failed to load courses');
		}
		setLoading(false);
	}, []);

	return (
		<UnifiedDataContext.Provider value={{ coursesData, setCoursesData, loading, error, refreshCourses }}>
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
