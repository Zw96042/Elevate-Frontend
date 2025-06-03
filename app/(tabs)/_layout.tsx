import { View, Text, ImageBackground } from 'react-native'
import React from 'react'
import { Tabs } from 'expo-router'
import { images } from '@/constants/images'
import { Image } from 'react-native'
import { icons } from '@/constants/icons'
import { Ionicons } from '@expo/vector-icons'

const _layout = () => {
  return (
    <Tabs
      screenOptions={{
        tabBarShowLabel: false,
        tabBarItemStyle: {
          flex: 1,
        },
        tabBarStyle: {
          backgroundColor: '#302c2c',
          borderTopWidth: 0,
          height: 70,
          paddingBottom: 8,
          position: 'absolute',
        }
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
  )
}

export default _layout