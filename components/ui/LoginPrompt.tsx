/**
 * Login Prompt Component
 * Shows when user needs to log in with credentials
 */

import React from 'react';
import { View, Text, TouchableOpacity, useColorScheme } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';

interface LoginPromptProps {
  message?: string;
  onLoginPress?: () => void;
}

export const LoginPrompt: React.FC<LoginPromptProps> = ({
  message = 'Please log in with your Skyward credentials to view your courses.',
  onLoginPress
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const handleLoginPress = () => {
    if (onLoginPress) {
      onLoginPress();
    } else {
      // For now, show alert since login screen doesn't exist yet
      // TODO: Navigate to login screen when implemented
      alert('Login screen not implemented yet. Please use the settings to configure credentials.');
    }
  };

  return (
    <View className="items-center justify-center p-8">
      <View className={`w-20 h-20 rounded-full ${isDark ? 'bg-blue-900' : 'bg-blue-100'} items-center justify-center mb-6`}>
        <Ionicons 
          name="log-in-outline" 
          size={40} 
          color={isDark ? '#3b82f6' : '#2563eb'} 
        />
      </View>
      
      <Text className={`text-xl font-semibold mb-3 text-center ${isDark ? 'text-white' : 'text-gray-900'}`}>
        Welcome to Elevate
      </Text>
      
      <Text className={`text-sm text-center mb-8 ${isDark ? 'text-gray-300' : 'text-gray-600'} leading-5`}>
        {message}
      </Text>

      <TouchableOpacity
        onPress={handleLoginPress}
        className={`px-8 py-4 rounded-xl ${isDark ? 'bg-blue-600' : 'bg-blue-500'} flex-row items-center shadow-lg`}
      >
        <Ionicons name="log-in-outline" size={20} color="white" />
        <Text className="text-white font-semibold ml-3 text-base">Log In to Skyward</Text>
      </TouchableOpacity>
      
      <Text className={`text-xs text-center mt-6 ${isDark ? 'text-gray-400' : 'text-gray-500'}`}>
        Use your school district Skyward credentials
      </Text>
    </View>
  );
};

export default LoginPrompt;
