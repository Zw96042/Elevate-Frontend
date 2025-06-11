import { View, Text, TouchableOpacity, useColorScheme } from 'react-native'
import React from 'react'
import { Tabs } from 'expo-router'
import { Ionicons } from '@expo/vector-icons'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import { BottomSheetModalProvider } from '@gorhom/bottom-sheet'
import BottomSheet, { BottomSheetBackdrop, BottomSheetFlatList } from '@gorhom/bottom-sheet'
import { useBottomSheet, BottomSheetProvider, TermLabel } from '@/context/BottomSheetContext'
import { colors } from '@/utils/colorTheme'

const terms: TermLabel[] = ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades'];



const InnerLayout = () => {
  const { selectedCategory, setSelectedCategory, bottomSheetRef } = useBottomSheet()
  const colorScheme = useColorScheme()
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light

  return (
    <>
      <Tabs
        screenOptions={{
          tabBarShowLabel: false,
          tabBarItemStyle: {
            flex: 1,
          },
          tabBarStyle: {
            borderTopWidth: 0,
            height: 70,
            paddingBottom: 8,
            position: 'absolute',
          },
          tabBarBackground: () => (
            <View className="flex-1 bg-nav border-t border-gray-200 dark:border-transparent" />
          ),
        }}
      >
        <Tabs.Screen 
          name="index"
          options={{
            title: "Courses",
            headerShown: false,
            tabBarIcon: ({ focused }) => (
              <View className="items-center justify-center w-[180%] mt-5 h-[80%]">
                <Ionicons name="school-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>Courses</Text>
              </View>
            )
          }}
        />
        <Tabs.Screen 
          name="assignments"
          options={{
            title: "Assignments",
            headerShown: false,
            tabBarIcon: ({ focused }) => (
              <View className="items-center justify-center w-[240%] mt-5 h-[80%]">
                <Ionicons name="document-text-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>Assignments</Text>
              </View>
            )
          }}
        />
        <Tabs.Screen 
          name="inbox"
          options={{
            title: "Inbox",
            headerShown: false,
            tabBarIcon: ({ focused }) => (
              <View className="items-center justify-center w-[180%] mt-5 h-[80%]">
                <Ionicons name="file-tray-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>Inbox</Text>
              </View>
            )
          }}
        />
        <Tabs.Screen 
          name="profile"
          options={{
            title: "Settings",
            headerShown: false,
            tabBarIcon: ({ focused }) => (
              <View className="items-center justify-center w-[180%] mt-5 h-[80%]">
                <Ionicons name="settings-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>Settings</Text>
              </View>
            )
          }}
        />
      </Tabs>
      <BottomSheet
        ref={bottomSheetRef}
        index={-1}
        snapPoints={['42%']}
        enablePanDownToClose={true}
        backgroundStyle={{ backgroundColor: cardColor }}
        enableOverDrag={false}
        style={{ zIndex: 1 }}
        
        backdropComponent={(props) => (
          <BottomSheetBackdrop
            {...props}
            disappearsOnIndex={-1}
            appearsOnIndex={0}
          />
        )}
      >
       <BottomSheetFlatList
          data={terms}
          keyExtractor={(item) => item}
          renderItem={({ item }) => (
            <TouchableOpacity
              onPress={() => {
                setSelectedCategory(item);
                bottomSheetRef.current?.close();
              }}
              className="px-5 py-4"
            >
              <Text className="text-main text-lg">{item}</Text>
            </TouchableOpacity>
          )}
          scrollEnabled={false}
          className={'bg-cardColor'}
        />
      </BottomSheet>
    </>
  )
}

const _layout = () => {
  return (
    <BottomSheetProvider>
      <BottomSheetModalProvider>
        <GestureHandlerRootView style={{ flex: 1 }}>
          <InnerLayout />
        </GestureHandlerRootView>
      </BottomSheetModalProvider>
    </BottomSheetProvider>
  )
}

export default _layout