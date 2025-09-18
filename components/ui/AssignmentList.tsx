/**
 * Assignment List Component
 * Handles display and management of assignment lists with filtering and caching
 */

import React, { useState, useEffect, useCallback } from 'react';
import { View, FlatList, RefreshControl, Text, TouchableOpacity, useColorScheme } from 'react-native';
import { Assignment, TermLabel } from '@/interfaces/interfaces';
import { CacheManager } from '@/lib/core/CacheManager';
import { ApiClient } from '@/lib/core/ApiClient';
import AssignmentCard from '@/components/AssignmentCard';
import SkeletonAssignment from '@/components/SkeletonAssignment';

interface AssignmentListProps {
  className: string;
  stuId: string;
  corNumId: string;
  section: string;
  gbId: string;
  selectedTerm: TermLabel;
  onAssignmentPress?: (assignment: Assignment) => void;
  showArtificialOnly?: boolean;
  artificialAssignments?: Assignment[];
}

export const AssignmentList: React.FC<AssignmentListProps> = ({
  className,
  stuId,
  corNumId,
  section,
  gbId,
  selectedTerm,
  onAssignmentPress,
  showArtificialOnly = false,
  artificialAssignments = [],
}) => {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const cacheKey = `assignments_${className}_${stuId}_${corNumId}_${section}_${gbId}_${selectedTerm}`;

  const fetchAssignments = useCallback(async (forceRefresh = false) => {
    try {
      setLoading(true);
      setError(null);

      // Check cache first unless force refresh
      if (!forceRefresh) {
        const cachedData = await CacheManager.get<Assignment[]>(cacheKey);
        if (cachedData) {
          setAssignments(cachedData);
          setLoading(false);
          return;
        }
      }

      // Fetch from API
      const response = await ApiClient.fetchGradeInfo({
        corNumId,
        stuId,
        section,
        gbId,
      });

      if (response.success && response.data) {
        const fetchedAssignments = response.data.assignments || [];
        
        // Cache the results
        await CacheManager.set(cacheKey, fetchedAssignments, 10 * 60 * 1000); // 10 minutes
        
        setAssignments(fetchedAssignments);
      } else {
        setError(response.error || 'Failed to fetch assignments');
        setAssignments([]);
      }
    } catch (err) {
      console.error('Error fetching assignments:', err);
      setError('Failed to load assignments');
      setAssignments([]);
    } finally {
      setLoading(false);
    }
  }, [cacheKey, corNumId, stuId, section, gbId]);

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    await fetchAssignments(true);
    setRefreshing(false);
  }, [fetchAssignments]);

  useEffect(() => {
    fetchAssignments();
  }, [fetchAssignments]);

  const getFilteredAssignments = () => {
    if (showArtificialOnly) {
      return artificialAssignments.filter(assignment => 
        assignment.term.toLowerCase().includes(selectedTerm.toLowerCase().split(' ')[0])
      );
    }

    const combined = [...assignments, ...artificialAssignments];
    return combined.filter(assignment => 
      assignment.term.toLowerCase().includes(selectedTerm.toLowerCase().split(' ')[0])
    );
  };

  const filteredAssignments = getFilteredAssignments();

  const renderAssignment = ({ item }: { item: Assignment }) => (
    <AssignmentCard
      editing={false} {...item}
      onPress={() => onAssignmentPress?.(item)}
      showClass={false}    />
  );

  const renderSkeletonItems = () => (
    <View>
      {Array.from({ length: 5 }).map((_, index) => (
        <SkeletonAssignment key={index} />
      ))}
    </View>
  );

  const renderEmptyState = () => (
    <View style={{
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      padding: 40,
    }}>
      <Text style={{
        fontSize: 18,
        fontWeight: '600',
        color: isDark ? '#9ca3af' : '#6b7280',
        textAlign: 'center',
        marginBottom: 8,
      }}>
        No Assignments
      </Text>
      <Text style={{
        fontSize: 14,
        color: isDark ? '#6b7280' : '#9ca3af',
        textAlign: 'center',
        lineHeight: 20,
      }}>
        {showArtificialOnly 
          ? 'No artificial assignments for this term'
          : 'No assignments found for this term'
        }
      </Text>
    </View>
  );

  const renderErrorState = () => (
    <View style={{
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      padding: 40,
    }}>
      <Text style={{
        fontSize: 18,
        fontWeight: '600',
        color: '#ef4444',
        textAlign: 'center',
        marginBottom: 8,
      }}>
        Error Loading Assignments
      </Text>
      <Text style={{
        fontSize: 14,
        color: isDark ? '#6b7280' : '#9ca3af',
        textAlign: 'center',
        lineHeight: 20,
        marginBottom: 16,
      }}>
        {error}
      </Text>
      <TouchableOpacity
        onPress={() => fetchAssignments(true)}
        style={{
          backgroundColor: '#3b82f6',
          paddingHorizontal: 20,
          paddingVertical: 10,
          borderRadius: 8,
        }}
      >
        <Text style={{
          color: '#ffffff',
          fontWeight: '500',
        }}>
          Retry
        </Text>
      </TouchableOpacity>
    </View>
  );

  if (loading && !refreshing) {
    return renderSkeletonItems();
  }

  if (error && !refreshing) {
    return renderErrorState();
  }

  return (
    <FlatList
      data={filteredAssignments}
      renderItem={renderAssignment}
      keyExtractor={(item, index) => item.id || `${item.name}-${index}`}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={handleRefresh}
          tintColor={isDark ? '#ffffff' : '#000000'}
        />
      }
      contentContainerStyle={{
        paddingHorizontal: 16,
        paddingBottom: 20,
      }}
      showsVerticalScrollIndicator={false}
      ListEmptyComponent={renderEmptyState}
      ItemSeparatorComponent={() => (
        <View style={{ height: 8 }} />
      )}
    />
  );
};
