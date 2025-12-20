import React, { createContext, useContext, useState, ReactNode } from 'react';

export type SortOption = 'Date' | 'Grade' | 'Category';
export type SortOrder = 'asc' | 'desc';
export type AssignmentType = 'missing' | 'noCount' | 'absent';

interface FilterContextType {
  // Sort options
  sortOption: SortOption;
  sortOrder: SortOrder;
  setSortOption: (option: SortOption) => void;
  setSortOrder: (order: SortOrder) => void;
  
  // Filter options
  selectedCategories: string[];
  setSelectedCategories: (categories: string[]) => void;
  availableCategories: string[];
  setAvailableCategories: (categories: string[]) => void;
  
  // Assignment type filters
  selectedAssignmentTypes: AssignmentType[];
  setSelectedAssignmentTypes: (types: AssignmentType[]) => void;
  toggleAssignmentType: (type: AssignmentType) => void;
  
  // Helper functions
  toggleCategory: (category: string) => void;
  clearFilters: () => void;
  hasActiveFilters: () => boolean;
  
  // Sort helper
  handleSortChange: (newSortOption: SortOption) => void;
}

const FilterContext = createContext<FilterContextType | undefined>(undefined);

interface FilterProviderProps {
  children: ReactNode;
}

export const FilterProvider: React.FC<FilterProviderProps> = ({ children }) => {
  const [sortOption, setSortOption] = useState<SortOption>('Date');
  const [sortOrder, setSortOrder] = useState<SortOrder>('desc'); // desc = recent to oldest for dates
  const [selectedCategories, setSelectedCategories] = useState<string[]>([]);
  const [availableCategories, setAvailableCategories] = useState<string[]>([]);
  const [selectedAssignmentTypes, setSelectedAssignmentTypes] = useState<AssignmentType[]>([]);

  const toggleCategory = (category: string) => {
    setSelectedCategories(prev => 
      prev.includes(category) 
        ? prev.filter(c => c !== category)
        : [...prev, category]
    );
  };

  const toggleAssignmentType = (type: AssignmentType) => {
    setSelectedAssignmentTypes(prev => 
      prev.includes(type) 
        ? prev.filter(t => t !== type)
        : [...prev, type]
    );
  };

  const clearFilters = () => {
    setSelectedCategories([]);
    setSelectedAssignmentTypes([]);
    setSortOption('Date');
    setSortOrder('desc');
  };

  const hasActiveFilters = () => {
    return selectedCategories.length > 0 || 
           selectedAssignmentTypes.length > 0 || 
           sortOption !== 'Date' || 
           sortOrder !== 'desc';
  };

  const handleSortChange = (newSortOption: SortOption) => {
    if (sortOption === newSortOption) {
      // If same option, toggle order
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      // New option, set default order
      setSortOption(newSortOption);
      if (newSortOption === 'Grade') {
        setSortOrder('desc'); // Grades default to highest first
      } else if (newSortOption === 'Date') {
        setSortOrder('desc'); // Dates default to recent first (newest to oldest)
      } else {
        setSortOrder('asc'); // Categories default to A-Z
      }
    }
  };

  const value: FilterContextType = {
    sortOption,
    sortOrder,
    setSortOption,
    setSortOrder,
    selectedCategories,
    setSelectedCategories,
    availableCategories,
    setAvailableCategories,
    selectedAssignmentTypes,
    setSelectedAssignmentTypes,
    toggleAssignmentType,
    toggleCategory,
    clearFilters,
    hasActiveFilters,
    handleSortChange,
  };

  return (
    <FilterContext.Provider value={value}>
      {children}
    </FilterContext.Provider>
  );
};

export const useFilter = (): FilterContextType => {
  const context = useContext(FilterContext);
  if (!context) {
    throw new Error('useFilter must be used within a FilterProvider');
  }
  return context;
};