import { useColorScheme, TouchableOpacity, Text, LayoutAnimation, View, TextInput, ScrollView, Keyboard, findNodeHandle } from "react-native";
import { Ionicons } from '@expo/vector-icons';
import { BottomSheetProvider, useBottomSheet, TermLabel } from "@/context/BottomSheetContext";
import { AddSheetProvider, useAddAssignmentSheet } from "@/context/AddAssignmentSheetContext";
import BottomSheet, { BottomSheetModalProvider, BottomSheetBackdrop, BottomSheetFlatList, BottomSheetView, TouchableWithoutFeedback } from "@gorhom/bottom-sheet";
import { colors } from "@/utils/colorTheme";
import { Stack } from "expo-router";
import './globals.css';
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { useEffect, useState, useRef } from "react";
import Animated, { useSharedValue, useAnimatedStyle, withTiming } from 'react-native-reanimated';
import * as Burnt from "burnt";
import 'react-native-reanimated'
import 'react-native-gesture-handler'
import { AddClassSheetProvider } from "@/context/AddClassSheetContext";
import { UnifiedDataProvider } from '@/context/UnifiedDataContext';


const terms: TermLabel[] = ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades'];

function InnerLayout() {
  const { selectedCategory, setSelectedCategory, bottomSheetRef } = useBottomSheet();
  const colorScheme = useColorScheme();
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light;

  // Fix missing refs and state
  // Use addSheetRef from context so openModal can trigger modal open from anywhere
  const { categories, setCategory, category, addSheetRef, name, setName, grade, setGrade, outOf, setOutOf, onSubmit } = useAddAssignmentSheet();
  const [currentSnapPosition, setCurrentSnapPosition] = useState('hidden');
  const [modalClosedByOutsideTap, setModalClosedByOutsideTap] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isClosingModal, setIsClosingModal] = useState(false);
  const [keyboardListenersDisabled, setKeyboardListenersDisabled] = useState(false);
  const lastSubmitTime = useRef<number>(0);
  const submitButtonRef = useRef<any>(null);
  const nameInputRef = useRef<any>(null);
  const gradeInputRef = useRef<any>(null);
  const outOfInputRef = useRef<any>(null);
  // Remove local name state, use context
  // category and setCategory now come from context
  // grade and outOf now come from context
  // ...removed duplicate destructuring...

  // Handler for sheet changes
  const handleSheetChanges = (index: number) => {
    if (index === -1) {
      setCurrentSnapPosition('hidden');
      setModalClosedByOutsideTap(true);
      setIsSubmitting(false); // Reset submitting flag when modal closes
      setIsClosingModal(false); // Reset closing flag when modal is closed
      // Re-enable keyboard listeners after modal is fully closed
      setTimeout(() => setKeyboardListenersDisabled(false), 500);
    } else {
      setCurrentSnapPosition('54%');
      setModalClosedByOutsideTap(false);
      setIsClosingModal(false); // Reset closing flag when modal opens
      setKeyboardListenersDisabled(false); // Ensure listeners are enabled when modal opens
    }
  };

  // Keyboard handling for modal snap position
  useEffect(() => {
    const showSub = Keyboard.addListener('keyboardDidShow', () => {
      // Completely ignore keyboard events if listeners are disabled
      if (keyboardListenersDisabled) {
        console.log('🚫 Keyboard show event ignored - listeners disabled');
        return;
      }
      
      // Ignore if recent submit (within 2 seconds)
      const now = Date.now();
      if (now - lastSubmitTime.current < 2000) {
        console.log('🚫 Keyboard show event ignored - recent submit');
        return;
      }
      
      if (
        !modalClosedByOutsideTap &&
        !isClosingModal &&
        !isSubmitting &&
        currentSnapPosition !== '90%' &&
        currentSnapPosition !== 'hidden'
      ) {
        addSheetRef.current?.snapToPosition('90%', { duration: 150 });
        setCurrentSnapPosition('90%');
      }
    });

    const hideSub = Keyboard.addListener('keyboardDidHide', () => {
      // Completely ignore keyboard events if listeners are disabled
      if (keyboardListenersDisabled) {
        console.log('🚫 Keyboard hide event ignored - listeners disabled');
        return;
      }
      
      // Ignore if recent submit (within 2 seconds)
      const now = Date.now();
      if (now - lastSubmitTime.current < 2000) {
        console.log('🚫 Keyboard hide event ignored - recent submit');
        return;
      }
      
      if (modalClosedByOutsideTap) {
        setModalClosedByOutsideTap(false);
        return;
      }
      if (isSubmitting || isClosingModal) {
        // Don't adjust modal position if we're submitting or closing
        return;
      }
      if (currentSnapPosition === '90%') {
        addSheetRef.current?.snapToPosition('54%', { duration: 150 });
        setCurrentSnapPosition('54%');
      }
    });

    return () => {
      showSub.remove();
      hideSub.remove();
    };
  }, [currentSnapPosition, modalClosedByOutsideTap, isSubmitting, isClosingModal, keyboardListenersDisabled]);
  return (
    <UnifiedDataProvider>
      <TouchableWithoutFeedback onPress={() => {
                Keyboard.dismiss();
                addSheetRef.current?.close();
                setCurrentSnapPosition('hidden');
              }} accessible={false}>
        <View className="flex-1">
          <Stack
            screenOptions={{
              headerTintColor: '#ffffff',
              headerStyle: { backgroundColor: '#2563eb' },
              headerTitleStyle: {
                fontWeight: 'bold',
                fontSize: 18,
              },
            }}
          >
            <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
            <Stack.Screen name="inbox/[message]" options={{
              headerShown: true,
              title: "Message",
              headerStyle: {
                backgroundColor: '#2563eb'
              },
              headerTintColor: '#ffffff',
              headerTitleStyle: {
                fontWeight: 'bold',
                fontSize: 18,
              },
              headerBackTitle: 'Inbox'
            }} />
            <Stack.Screen name="assignments/[assignment]" options={{
              headerShown: true,
              headerStyle: {
                backgroundColor: '#2563eb'
              },
              headerTintColor: '#ffffff',
              headerTitleStyle: {
                fontWeight: 'bold',
                fontSize: 18,
              },
            }} />
          </Stack>
          <BottomSheet
            ref={bottomSheetRef}
            index={-1}
            snapPoints={['54%']}
            enablePanDownToClose={true}
            enableDynamicSizing={false}
            backgroundStyle={{ backgroundColor: cardColor }}
            overDragResistanceFactor={1}
            style={{ zIndex: 1 }}
            backdropComponent={(props) => (
              <BottomSheetBackdrop
                {...props}
                disappearsOnIndex={-1}
                appearsOnIndex={0}
              />
            )}
          >
            <View className="px-5 pb-4 bg-cardColor">
              <Text className="text-2xl text-main">Select Term</Text>
              <View className='my-4 border-slate-600 border-[0.5px]'></View>
              <BottomSheetFlatList
                data={terms}
                keyExtractor={(item) => item}
                renderItem={({ item }) => {
                  const isSelected = item === selectedCategory;

                  return (
                    <TouchableOpacity
                      onPress={() => {
                        setSelectedCategory(item);
                        bottomSheetRef.current?.close();
                      }}
                      className={`w-full px-4 py-4 mb-3 rounded-md flex-row items-center ${
                        isSelected ? 'bg-highlight' : 'bg-primary'
                      }`}
                    >
                      <Ionicons name="calendar-outline" size={20} color={isSelected ? '#fff' : '#64748b'} className="mr-3" />
                      <Text className={`text-base ${isSelected ? 'text-highlightText font-bold' : 'text-main'}`}>
                        {item}
                      </Text>
                    </TouchableOpacity>
                  );
                }}
                scrollEnabled={false}
                showsVerticalScrollIndicator={false}
              />
            </View>
          </BottomSheet>
          <BottomSheet
            ref={addSheetRef}
            index={-1}
            snapPoints={['54%']}
            enablePanDownToClose={true}
            backgroundStyle={{ backgroundColor: cardColor }}
            enableDynamicSizing={false}
            overDragResistanceFactor={1}
            enableHandlePanningGesture={true}
            style={{ zIndex: 2 }}
            keyboardBehavior={'extend'}
            onChange={handleSheetChanges}
            detached={true}
            backdropComponent={(props) => (
              <TouchableWithoutFeedback onPress={() => {
                Keyboard.dismiss();
                addSheetRef.current?.close();
                setCurrentSnapPosition('hidden');
                setModalClosedByOutsideTap(true);
              }}>
                <BottomSheetBackdrop
                  {...props}
                  disappearsOnIndex={-1}
                  appearsOnIndex={0}
                />
              </TouchableWithoutFeedback>
            )}
          >
            <TouchableWithoutFeedback onPress={() => {
              Keyboard.dismiss();
              addSheetRef.current?.snapToPosition('54%', { duration: 350 });
              setCurrentSnapPosition('54%');
            }}>
              <BottomSheetView className="bg-cardColor p-4">
                 <Text className="text-2xl text-main">Add New Assignment</Text>
                 <View className='mb-4 mt-2 border-slate-600 border-[0.5px]'></View>
                  <View className="mb-5">
                    <Text className="text-sm  text-main mb-1" >Assignment Name</Text>
                    <TextInput
                      ref={nameInputRef}
                      className="rounded-md px-4 py-2 text-main bg-primary"
                      onChangeText={setName}
                      value={name}
                      editable
                      placeholder="Assignment Name"
                      autoCorrect={false}
                      autoComplete="off"
                      autoCapitalize="none"
                      spellCheck={false}
                    />
                  </View>
                  <View className="mb-5">
                    <Text className="text-sm text-main mb-1">Category</Text>
                    <View className="flex-row flex-wrap gap-2">
                      {categories.map((cat) => (
                        <TouchableOpacity
                          key={cat}
                          onPress={() => setCategory(cat)}
                          className={`px-3 py-1 rounded-full border ${
                            category === cat
                              ? 'bg-highlight border-highlight'
                              : 'border-accent'
                          }`}
                        >
                          <Text
                            className={`text-sm ${
                              category === cat
                                ? 'text-highlightText font-bold'
                                : 'text-main'
                            }`}
                          >
                            {cat}
                          </Text>
                        </TouchableOpacity>
                      ))}
                    </View>
                  </View>
                  <View className="mb-5">
                    <Text className="text-sm text-main mb-1">Grade</Text>
                    <TextInput
                      ref={gradeInputRef}
                      className="rounded-md px-4 py-2 text-main bg-primary"
                      onChangeText={(i) => setGrade(i)}
                      value={grade}
                      editable
                      placeholder="Grade"
                      keyboardType="numeric"
                    />
                  </View>
                  <View className="mb-5">
                    <Text className="text-sm text-main mb-1">Out Of</Text>
                    <TextInput
                      ref={outOfInputRef}
                      className="rounded-md px-4 py-2 text-main bg-primary"
                      onChangeText={(i) => setOutOf(parseFloat(i) || 0)}
                      value={outOf.toString()}
                      editable
                      placeholder="Out Of"
                      keyboardType="numeric"
                    />
                  </View>
                  <TouchableOpacity
                    ref={submitButtonRef}
                    className="bg-highlight py-3 rounded-md mt-2"
                    onPress={async () => {
                      console.log('🔘 Submit button pressed - disabling keyboard listeners');
                      
                      // Record submit time for timestamp-based protection
                      lastSubmitTime.current = Date.now();
                      
                      // FIRST: Disable keyboard listeners completely
                      setKeyboardListenersDisabled(true);
                      
                      // Set flags to prevent any remaining interference
                      setIsSubmitting(true);
                      setIsClosingModal(true);
                      
                      // Blur all text inputs to ensure they lose focus
                      nameInputRef.current?.blur();
                      gradeInputRef.current?.blur();
                      outOfInputRef.current?.blur();
                      
                      // Dismiss keyboard immediately and aggressively multiple times
                      Keyboard.dismiss();
                      
                      // Multiple keyboard dismissals to ensure it works on real devices
                      setTimeout(() => Keyboard.dismiss(), 50);
                      setTimeout(() => Keyboard.dismiss(), 100);
                      
                      // Delay before submit to ensure keyboard is gone
                      setTimeout(async () => {
                        try {
                          console.log('📤 Executing onSubmit');
                          // Final keyboard dismissal before submit
                          Keyboard.dismiss();
                          await onSubmit();
                          console.log('✅ Submit completed successfully');
                        } catch (error) {
                          console.error('❌ Error submitting assignment:', error);
                        } finally {
                          // Reset flags after submission is complete
                          setIsSubmitting(false);
                          setIsClosingModal(false);
                          // Keep listeners disabled for a bit longer to ensure modal closes
                          console.log('🏁 Submit process finished');
                        }
                      }, 200);
                    }}
                  >
                    <Text className="text-center text-highlightText font-bold text-lg">Add Assignment</Text>
                  </TouchableOpacity>
              </BottomSheetView>
            </TouchableWithoutFeedback>
          </BottomSheet>
        </View>
      </TouchableWithoutFeedback>
    </UnifiedDataProvider>
  );
// ...existing code ends here...
}

export default function RootLayout() {
  return (
      <AddClassSheetProvider>
        <AddSheetProvider>
          <BottomSheetProvider>
            <BottomSheetModalProvider>
              
                <GestureHandlerRootView style={{ flex: 1 }}>
                  
                    <InnerLayout />
                </GestureHandlerRootView>
              
            </BottomSheetModalProvider>
          </BottomSheetProvider>
          </AddSheetProvider>
      </AddClassSheetProvider>
    )
}