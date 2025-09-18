/**
 * Reusable Modal Template System
 * Flexible modal components that can be easily configured for different use cases
 */

import React, { ReactNode } from 'react';
import {
  View,
  Text,
  Modal,
  TouchableOpacity,
  ScrollView,
  KeyboardAvoidingView,
  Platform,
  useColorScheme,
  ViewStyle,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';

// Modal configuration types
export interface ModalConfig {
  title: string;
  subtitle?: string;
  size?: 'small' | 'medium' | 'large' | 'fullscreen';
  showCloseButton?: boolean;
  dismissOnBackdrop?: boolean;
  showHeader?: boolean;
  showFooter?: boolean;
  animation?: 'slide' | 'fade' | 'none';
}

export interface ModalAction {
  text: string;
  onPress: () => void;
  style?: 'default' | 'primary' | 'destructive';
  disabled?: boolean;
}

export interface BaseModalProps {
  visible: boolean;
  onClose: () => void;
  config: ModalConfig;
  actions?: ModalAction[];
  children: ReactNode;
}

/**
 * Base Modal Component
 */
export const BaseModal: React.FC<BaseModalProps> = ({
  visible,
  onClose,
  config,
  actions = [],
  children,
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const getModalSize = (): ViewStyle => {
    switch (config.size) {
      case 'small':
        return { width: '80%', maxHeight: '40%' };
      case 'medium':
        return { width: '90%', maxHeight: '60%' };
      case 'large':
        return { width: '95%', maxHeight: '80%' };
      case 'fullscreen':
        return { width: '100%', height: '100%' };
      default:
        return { width: '90%', maxHeight: '70%' };
    }
  };

  const getAnimationType = (): 'slide' | 'fade' | 'none' => {
    return config.animation || 'slide';
  };

  const handleBackdropPress = () => {
    if (config.dismissOnBackdrop !== false) {
      onClose();
    }
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType={getAnimationType()}
      onRequestClose={onClose}
    >
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
        <TouchableOpacity
          style={{
            flex: 1,
            backgroundColor: 'rgba(0, 0, 0, 0.5)',
            justifyContent: 'center',
            alignItems: 'center',
            padding: 20,
          }}
          activeOpacity={1}
          onPress={handleBackdropPress}
        >
          <TouchableOpacity
            style={[
              {
                backgroundColor: isDark ? '#1a1a1a' : '#ffffff',
                borderRadius: 16,
                overflow: 'hidden',
                shadowColor: '#000',
                shadowOffset: { width: 0, height: 4 },
                shadowOpacity: 0.25,
                shadowRadius: 12,
                elevation: 8,
              },
              getModalSize(),
            ]}
            activeOpacity={1}
          >
            {/* Header */}
            {config.showHeader !== false && (
              <View
                style={{
                  flexDirection: 'row',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: 20,
                  borderBottomWidth: 1,
                  borderBottomColor: isDark ? '#333' : '#e5e5e5',
                }}
              >
                <View style={{ flex: 1 }}>
                  <Text
                    style={{
                      fontSize: 18,
                      fontWeight: '600',
                      color: isDark ? '#ffffff' : '#000000',
                      marginBottom: config.subtitle ? 4 : 0,
                    }}
                  >
                    {config.title}
                  </Text>
                  {config.subtitle && (
                    <Text
                      style={{
                        fontSize: 14,
                        color: isDark ? '#a0a0a0' : '#666666',
                      }}
                    >
                      {config.subtitle}
                    </Text>
                  )}
                </View>
                
                {config.showCloseButton !== false && (
                  <TouchableOpacity
                    onPress={onClose}
                    style={{
                      padding: 8,
                      borderRadius: 8,
                    }}
                  >
                    <Ionicons
                      name="close"
                      size={24}
                      color={isDark ? '#a0a0a0' : '#666666'}
                    />
                  </TouchableOpacity>
                )}
              </View>
            )}

            {/* Content */}
            <ScrollView
              style={{
                flex: 1,
                padding: 20,
              }}
              showsVerticalScrollIndicator={false}
            >
              {children}
            </ScrollView>

            {/* Footer with Actions */}
            {config.showFooter !== false && actions.length > 0 && (
              <View
                style={{
                  flexDirection: 'row',
                  padding: 20,
                  borderTopWidth: 1,
                  borderTopColor: isDark ? '#333' : '#e5e5e5',
                  gap: 12,
                }}
              >
                {actions.map((action, index) => (
                  <TouchableOpacity
                    key={index}
                    onPress={action.onPress}
                    disabled={action.disabled}
                    style={[
                      {
                        flex: 1,
                        paddingVertical: 12,
                        paddingHorizontal: 16,
                        borderRadius: 8,
                        alignItems: 'center',
                        justifyContent: 'center',
                      },
                      action.style === 'primary' && {
                        backgroundColor: '#007AFF',
                      },
                      action.style === 'destructive' && {
                        backgroundColor: '#FF3B30',
                      },
                      action.style === 'default' && {
                        backgroundColor: 'transparent',
                        borderWidth: 1,
                        borderColor: isDark ? '#666' : '#ccc',
                      },
                      action.disabled && {
                        opacity: 0.5,
                      },
                    ]}
                  >
                    <Text
                      style={[
                        {
                          fontSize: 16,
                          fontWeight: '500',
                        },
                        action.style === 'primary' && {
                          color: '#ffffff',
                        },
                        action.style === 'destructive' && {
                          color: '#ffffff',
                        },
                        action.style === 'default' && {
                          color: isDark ? '#ffffff' : '#000000',
                        },
                      ]}
                    >
                      {action.text}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            )}
          </TouchableOpacity>
        </TouchableOpacity>
      </KeyboardAvoidingView>
    </Modal>
  );
};
