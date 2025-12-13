import React from 'react';
import { View, ViewStyle } from 'react-native';

interface ContextMenuWrapperProps {
  children: React.ReactNode;
  style?: ViewStyle;
  className?: string;
}

/**
 * Wrapper component that ensures context menus don't get clipped by parent containers.
 * This component sets proper overflow and z-index values to prevent clipping during animations.
 */
const ContextMenuWrapper: React.FC<ContextMenuWrapperProps> = ({ 
  children, 
  style, 
  className 
}) => {
  return (
    <View 
      className={className}
      style={[
        {
          overflow: 'visible',
          zIndex: 1000,
        },
        style
      ]}
    >
      {children}
    </View>
  );
};

export default ContextMenuWrapper;