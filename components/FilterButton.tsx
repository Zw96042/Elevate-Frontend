import React, { useMemo } from 'react';
import { View, Text, TouchableOpacity, useColorScheme } from 'react-native';
import { ContextMenu, Host, Button, Submenu, Image } from "@expo/ui/swift-ui";
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
    // <Host>
    // <View className="flex-row items-center rounded-full overflow-hidden">
    // <Host>
    // <Host>
    // <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 6.5 }}>
    //    {/* <Button systemImage='slider.horizontal.3'>
    //     <Text></Text>
    //   </Button>  */}
    //   <SymbolView 
    //     name="slider.horizontal.3" 
    //     size={22} 
    //     style={{  width: 22, height: 22}}
    //   />
    // </View>
    // </Host>
    // <HeaderButton>
    //   <SymbolView 
    //     name="slider.horizontal.3" 
    //     size={22} 
    //     style={{ width: 22, height: 22 }}
    //   />
    // </HeaderButton>
    <Host matchContents>
      <Image systemName='slider.horizontal.3' size={22} modifiers={[
        padding({
          trailing: 0,
          leading: 3,
        })
      ]}/>
    </Host>

      // <Ionicons name="options-outline" size={22} style={{ width: 22, height: 22, marginRight: 20 }}  color={theme === 'dark' ? '#fff' : '#000'}/>
      /* <SymbolView 
        name="slider.horizontal.3" 
        size={22} 
        style={{  width: 22, height: 22, marginLeft: 15}}
      /> */
      /* </Host> */
    // </View>
    // </Host>
  );

  return (
    <Host matchContents modifiers={[
      glassEffect({
          glass: {
            variant: 'identity'
          }
        })
    ]}>
      <ContextMenu modifiers={[
        buttonStyle('plain'),
        padding({
          leading: 7,
          trailing: 5
        })
      ]} >
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
              button={<Button systemImage="line.3.horizontal.decrease">Filter</Button>}
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

        <ContextMenu.Trigger >
          {/* <TouchableOpacity 
            style={{ 
              paddingLeft: 12,
              paddingRight: 12,
              borderRadius: 8
            }}
            hitSlop={{ top: 8, bottom: 16, left: 16, right: 8 }}
          > */}
            {/* <DecreasingBarsIcon /> */}
          {/* </TouchableOpacity> */}
           {/* <View className="flex-row items-center rounded-full overflow-hidden ">
             <TouchableOpacity
                 className="px-2 py-2"
                 hitSlop={0}
               >
                 <SymbolView size={22} name="slider.horizontal.3" />
               </TouchableOpacity>
           </View> */}
           <Button variant="plain" systemImage='slider.horizontal.3' modifiers={[
            // opacity({
            //   0
            // })
            buttonStyle('plain')
           ]}></Button>
        </ContextMenu.Trigger>
      </ContextMenu>
    </Host>
    // <View className="flex-row items-center rounded-full overflow-hidden ">
    //   <TouchableOpacity
    //       className="px-2 py-2"
    //       hitSlop={0}
    //     >
    //       <SymbolView size={22} name="slider.horizontal.3" />
    //     </TouchableOpacity>
    // </View>
  );
};

export default FilterButton;