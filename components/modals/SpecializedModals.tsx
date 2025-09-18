/**
 * Specialized Modal Components
 * Pre-configured modals for common use cases
 */

import React, { useState } from 'react';
import { View, Text, TextInput, useColorScheme } from 'react-native';
import { BaseModal, ModalConfig, ModalAction } from './BaseModal';
import { TermData, TermLabel } from '@/interfaces/interfaces';

// Assignment Modal
interface AssignmentModalProps {
  visible: boolean;
  onClose: () => void;
  onSubmit: (assignment: {
    name: string;
    grade: string;
    outOf: number;
    category: string;
    dueDate: string;
  }) => void;
  categories: string[];
  selectedCategory?: string;
}

export const AssignmentModal: React.FC<AssignmentModalProps> = ({
  visible,
  onClose,
  onSubmit,
  categories,
  selectedCategory = '',
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';
  
  const [name, setName] = useState('');
  const [grade, setGrade] = useState('');
  const [outOf, setOutOf] = useState('100');
  const [category, setCategory] = useState(selectedCategory);
  const [dueDate, setDueDate] = useState(new Date().toISOString().split('T')[0]);

  const handleSubmit = () => {
    if (!name.trim() || !grade.trim() || !category) return;
    
    onSubmit({
      name: name.trim(),
      grade: grade.trim(),
      outOf: parseFloat(outOf) || 100,
      category,
      dueDate,
    });

    // Reset form
    setName('');
    setGrade('');
    setOutOf('100');
    setCategory(selectedCategory);
    setDueDate(new Date().toISOString().split('T')[0]);
    onClose();
  };

  const config: ModalConfig = {
    title: 'Add Assignment',
    subtitle: 'Enter assignment details',
    size: 'medium',
    showCloseButton: true,
    dismissOnBackdrop: true,
  };

  const actions: ModalAction[] = [
    {
      text: 'Cancel',
      onPress: onClose,
      style: 'default',
    },
    {
      text: 'Add Assignment',
      onPress: handleSubmit,
      style: 'primary',
      disabled: !name.trim() || !grade.trim() || !category,
    },
  ];

  const inputStyle = {
    borderWidth: 1,
    borderColor: isDark ? '#444' : '#ddd',
    borderRadius: 8,
    padding: 12,
    marginBottom: 16,
    backgroundColor: isDark ? '#2a2a2a' : '#f9f9f9',
    color: isDark ? '#fff' : '#000',
    fontSize: 16,
  };

  return (
    <BaseModal
      visible={visible}
      onClose={onClose}
      config={config}
      actions={actions}
    >
      <View>
        <Text style={{ color: isDark ? '#fff' : '#000', marginBottom: 8, fontWeight: '500' }}>
          Assignment Name
        </Text>
        <TextInput
          style={inputStyle}
          value={name}
          onChangeText={setName}
          placeholder="Enter assignment name"
          placeholderTextColor={isDark ? '#888' : '#666'}
        />

        <Text style={{ color: isDark ? '#fff' : '#000', marginBottom: 8, fontWeight: '500' }}>
          Grade
        </Text>
        <TextInput
          style={inputStyle}
          value={grade}
          onChangeText={setGrade}
          placeholder="Enter grade"
          placeholderTextColor={isDark ? '#888' : '#666'}
          keyboardType="numeric"
        />

        <Text style={{ color: isDark ? '#fff' : '#000', marginBottom: 8, fontWeight: '500' }}>
          Out Of
        </Text>
        <TextInput
          style={inputStyle}
          value={outOf}
          onChangeText={setOutOf}
          placeholder="100"
          placeholderTextColor={isDark ? '#888' : '#666'}
          keyboardType="numeric"
        />

        <Text style={{ color: isDark ? '#fff' : '#000', marginBottom: 8, fontWeight: '500' }}>
          Category
        </Text>
        <View style={{ marginBottom: 16 }}>
          {categories.map((cat, index) => (
            <Text
              key={index}
              style={{
                padding: 12,
                backgroundColor: category === cat 
                  ? (isDark ? '#444' : '#e0e0e0') 
                  : 'transparent',
                color: isDark ? '#fff' : '#000',
                borderRadius: 8,
                marginBottom: 4,
              }}
              onPress={() => setCategory(cat)}
            >
              {cat}
            </Text>
          ))}
        </View>
      </View>
    </BaseModal>
  );
};

// Confirmation Modal
interface ConfirmationModalProps {
  visible: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  destructive?: boolean;
}

export const ConfirmationModal: React.FC<ConfirmationModalProps> = ({
  visible,
  onClose,
  onConfirm,
  title,
  message,
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  destructive = false,
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const config: ModalConfig = {
    title,
    size: 'small',
    showCloseButton: false,
    dismissOnBackdrop: false,
  };

  const actions: ModalAction[] = [
    {
      text: cancelText,
      onPress: onClose,
      style: 'default',
    },
    {
      text: confirmText,
      onPress: () => {
        onConfirm();
        onClose();
      },
      style: destructive ? 'destructive' : 'primary',
    },
  ];

  return (
    <BaseModal
      visible={visible}
      onClose={onClose}
      config={config}
      actions={actions}
    >
      <Text style={{ 
        color: isDark ? '#fff' : '#000', 
        fontSize: 16,
        lineHeight: 24,
        textAlign: 'center',
      }}>
        {message}
      </Text>
    </BaseModal>
  );
};

// Loading Modal
interface LoadingModalProps {
  visible: boolean;
  message?: string;
}

export const LoadingModal: React.FC<LoadingModalProps> = ({
  visible,
  message = 'Loading...',
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const config: ModalConfig = {
    title: '',
    size: 'small',
    showCloseButton: false,
    showHeader: false,
    showFooter: false,
    dismissOnBackdrop: false,
  };

  return (
    <BaseModal
      visible={visible}
      onClose={() => {}}
      config={config}
    >
      <View style={{ alignItems: 'center', padding: 20 }}>
        {/* You can add a loading spinner here */}
        <Text style={{ 
          color: isDark ? '#fff' : '#000', 
          fontSize: 16,
          textAlign: 'center',
        }}>
          {message}
        </Text>
      </View>
    </BaseModal>
  );
};
