/**
 * User-friendly error display component
 * Shows appropriate error messages and retry actions
 */

import React from 'react';
import { View, Text, TouchableOpacity, useColorScheme } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

interface ErrorDisplayProps {
  error: string;
  onRetry?: () => void;
  showRetryButton?: boolean;
  title?: string;
}

export const ErrorDisplay: React.FC<ErrorDisplayProps> = ({
  error,
  onRetry,
  showRetryButton = true,
  title = 'Something went wrong'
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  return (
    <View className="items-center justify-center">
      <View className={`w-16 h-16 rounded-full ${isDark ? 'bg-red-900' : 'bg-red-100'} items-center justify-center mb-4`}>
        <Ionicons 
          name="alert-circle-outline" 
          size={32} 
          color={isDark ? '#ef4444' : '#dc2626'} 
        />
      </View>
      
      <Text className={`text-lg font-semibold mb-2 text-center ${isDark ? 'text-white' : 'text-gray-900'}`}>
        {title}
      </Text>
      
      <Text className={`text-sm text-center mb-6 ${isDark ? 'text-gray-300' : 'text-gray-600'}`}>
        {error}
      </Text>

      {showRetryButton && onRetry && (
        <TouchableOpacity
          onPress={onRetry}
          className={`px-6 py-3 rounded-lg ${isDark ? 'bg-blue-600' : 'bg-blue-500'} flex-row items-center`}
        >
          <Ionicons name="refresh-outline" size={18} color="white" />
          <Text className="text-white font-medium ml-2">Try Again</Text>
        </TouchableOpacity>
      )}
    </View>
  );
};

export default ErrorDisplay;
