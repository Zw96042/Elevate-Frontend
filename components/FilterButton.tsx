import React, { useMemo } from 'react';
import { View, Text, TouchableOpacity, useColorScheme } from 'react-native';
import { ContextMenu, Host, Button, Submenu, Image, VStack, Text as SText, Divider } from "@expo/ui/swift-ui";
import { SymbolView } from "expo-symbols";
import { useFilter } from '@/context/FilterContext';
import Ionicons from '@expo/vector-icons/build/Ionicons';
import { buttonStyle, foregroundStyle, glassEffect, padding } from '@expo/ui/swift-ui/modifiers';
import { HeaderButton } from '@react-navigation/elements';
import { opacity } from 'react-native-reanimated/lib/typescript/Colors';

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
    selectedAssignmentTypes,
    toggleAssignmentType,
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

  return (
    <Host matchContents modifiers={[
      glassEffect({
          glass: {
            variant: 'identity'
          }
        })
    ]}>
      <ContextMenu modifiers={[
        buttonStyle('glass'),
        padding({
          leading: 7,
          trailing: 5
        })
      ]} >
        <ContextMenu.Items>
          <ContextMenu>
            <ContextMenu.Items>
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
            </ContextMenu.Items>
            <ContextMenu.Trigger>
              <Button
                role="default"
                systemImage="arrow.up.arrow.down"
              >
                Sort By
              </Button>

              <ContextMenu.Trigger>
                <Button
                role="default"
                systemImage="arrow.up.arrow.down"
              >
                {sortOption+". "}
                {sortOption === 'Date' 
                  ? (sortOrder === 'asc' ? 'Oldest on top' : 'Newest on top')
                  : (sortOrder === 'asc' ? 'Lowest on top' : 'Highest on top')
                }
              </Button>
              </ContextMenu.Trigger>
              
            </ContextMenu.Trigger>
          </ContextMenu>
          <Divider />
          {categories.length > 0 && (
            <ContextMenu>
              <ContextMenu.Items>
                <ContextMenu>
                  <ContextMenu.Items>
                    {categories.map((category) => (
                    <Button
                      key={category}
                      systemImage={selectedCategories.includes(category) ? "checkmark.circle.fill" : "circle"}
                      onPress={() => toggleCategory(category)}
                    >
                      {category}
                    </Button>
                  ))}
                  </ContextMenu.Items>
                  <ContextMenu.Trigger>
                    <SText>Categories</SText>
                  </ContextMenu.Trigger>
                </ContextMenu>
                <ContextMenu>
                  <ContextMenu.Items>
                    <Button
                      systemImage={selectedAssignmentTypes.includes('noCount') ? "checkmark.circle.fill" : "circle"}
                      onPress={() => toggleAssignmentType('noCount')}
                    >
                      No Count
                    </Button>
                    <Button
                      systemImage={selectedAssignmentTypes.includes('absent') ? "checkmark.circle.fill" : "circle"}
                      onPress={() => toggleAssignmentType('absent')}
                    >
                      Absent
                    </Button>
                    <Button
                      systemImage={selectedAssignmentTypes.includes('missing') ? "checkmark.circle.fill" : "circle"}
                      onPress={() => toggleAssignmentType('missing')}
                    >
                      Missing
                    </Button>
                  </ContextMenu.Items>
                  <ContextMenu.Trigger>
                    <SText >Assignment Types</SText>
                  </ContextMenu.Trigger>
                </ContextMenu>
                
              </ContextMenu.Items>
              <ContextMenu.Trigger>
                <Button systemImage="line.3.horizontal.decrease">
                  Filter {(selectedCategories.length + selectedAssignmentTypes.length) > 0 && `(${selectedCategories.length + selectedAssignmentTypes.length})`}
                </Button>
                <ContextMenu.Trigger>
                  <Button systemImage="line.3.horizontal.decrease">
                    {selectedCategories.length === 0 && selectedAssignmentTypes.length === 0
                      ? "All categories" 
                      : (() => {
                          const allFilters = [...selectedCategories];
                          if (selectedAssignmentTypes.includes('noCount')) allFilters.push('No Count');
                          if (selectedAssignmentTypes.includes('absent')) allFilters.push('Absent');
                          if (selectedAssignmentTypes.includes('missing')) allFilters.push('Missing');
                          return allFilters.length === 1 
                            ? allFilters[0]
                            : allFilters.join(", ");
                        })()
                    }
                  </Button>
                </ContextMenu.Trigger>
              </ContextMenu.Trigger>

            </ContextMenu>
          )}

          <Divider />
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

        <ContextMenu.Trigger >
           <Button variant="plain" systemImage='slider.horizontal.3' modifiers={[
            buttonStyle('plain')
           ]}></Button>
        </ContextMenu.Trigger>
      </ContextMenu>
    </Host>
  );
};

export default FilterButton;