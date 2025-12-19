import React, { useMemo } from 'react';
import { View, Text, TouchableOpacity, useColorScheme } from 'react-native';
import { ContextMenu, Host, Button, Submenu } from "@expo/ui/swift-ui";
import { SymbolView } from "expo-symbols";
import { useFilter } from '@/context/FilterContext';

interface FilterButtonProps {
  availableCategories?: string[];
}

const FilterButton: React.FC<FilterButtonProps> = ({ availableCategories = [] }) => {
  const theme = useColorScheme();
  const {
    sortOption,
    sortOrder,
    selectedCategories,
    availableCategories: contextCategories,
    setAvailableCategories,
    toggleCategory,
    clearFilters,
    hasActiveFilters,
    handleSortChange,
  } = useFilter();

  // Update available categories when prop changes
  React.useEffect(() => {
    if (availableCategories && availableCategories.length > 0) {
      setAvailableCategories(availableCategories);
    }
  }, [availableCategories, setAvailableCategories]);

  const categories = (availableCategories && availableCategories.length > 0) ? availableCategories : contextCategories;

  // Memoize the filter icon color based on active state

  // Custom decreasing bars icon using SymbolView
  const DecreasingBarsIcon = () => (
    <View style={{ width: 24, height: 24, justifyContent: 'center', alignItems: 'center' }}>
      <SymbolView 
        name="line.3.horizontal.decrease" 
        size={20} 
        tintColor={theme === 'dark' ? '#ffffff' : '#000000'}
      />
    </View>
  );

  return (
    <Host>
      <ContextMenu>
        <ContextMenu.Items>
          {/* Sort By Submenu */}
          <Submenu
            button={<Button systemImage="arrow.up.arrow.down">Sort By</Button>}
          >
            <Button
              systemImage={sortOption === 'Date' ? "checkmark" : "calendar"}
              onPress={() => handleSortChange('Date')}
            >
              Date {sortOption === 'Date' && (sortOrder === 'asc' ? '(Oldest)' : '(Newest)')}
            </Button>
            <Button
              systemImage={sortOption === 'Grade' ? "checkmark" : "number"}
              onPress={() => handleSortChange('Grade')}
            >
              Grade {sortOption === 'Grade' && (sortOrder === 'asc' ? '(Lowest)' : '(Highest)')}
            </Button>
            <Button
              systemImage={sortOption === 'Category' ? "checkmark" : "textformat"}
              onPress={() => handleSortChange('Category')}
            >
              Category {sortOption === 'Category' && (sortOrder === 'asc' ? '(A-Z)' : '(Z-A)')}
            </Button>
          </Submenu>

          {/* Filter By Categories Submenu */}
          {categories.length > 0 && (
            <Submenu
              button={<Button systemImage="line.3.horizontal.decrease.circle">Filter</Button>}
            >
              {categories.map((category) => (
                <Button
                  key={category}
                  systemImage={selectedCategories.includes(category) ? "checkmark.circle.fill" : "circle"}
                  onPress={() => toggleCategory(category)}
                >
                  {category}
                </Button>
              ))}
            </Submenu>
          )}

          {/* Reset Section */}
          {hasActiveFilters() && (
            <Button
              systemImage="arrow.counterclockwise"
              role="destructive"
              onPress={clearFilters}
            >
              Reset
            </Button>
          )}
        </ContextMenu.Items>

        <ContextMenu.Trigger>
          <TouchableOpacity 
            style={{ 
              padding: 8,
              borderRadius: 8,
              backgroundColor: 'transparent'
            }}
            hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
          >
            <DecreasingBarsIcon />
          </TouchableOpacity>
        </ContextMenu.Trigger>
      </ContextMenu>
    </Host>
  );
};

export default FilterButton;