import { useColorScheme, TouchableOpacity, Text, LayoutAnimation, View, TextInput, ScrollView, Keyboard } from "react-native";
import { Ionicons } from '@expo/vector-icons';
import { BottomSheetProvider, useBottomSheet, TermLabel } from "@/context/BottomSheetContext";
import { AddSheetProvider, useAddAssignmentSheet } from "@/context/AddAssignmentSheetContext";
import BottomSheet, { BottomSheetModalProvider, BottomSheetBackdrop, BottomSheetFlatList, BottomSheetView, TouchableWithoutFeedback } from "@gorhom/bottom-sheet";
import { colors } from "@/utils/colorTheme";
import { Stack } from "expo-router";
import './globals.css';
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { useEffect, useState } from "react";
import Animated, { useSharedValue, useAnimatedStyle, withTiming } from 'react-native-reanimated';


const terms: TermLabel[] = ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades'];

function InnerLayout() {
  const { selectedCategory, setSelectedCategory, bottomSheetRef } = useBottomSheet();
  const colorScheme = useColorScheme();
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light;

  const {
    addSheetRef,
    name,
    setName,
    grade,
    setGrade,
    outOf,
    setOutOf,
    category,
    setCategory,
    onSubmit,
    term,
    className,
    categories,
    modalData
  } = useAddAssignmentSheet();

  const [currentSnapPosition, setCurrentSnapPosition] = useState<'hidden' | '54%' | '90%'>('hidden');
  const [modalClosedByOutsideTap, setModalClosedByOutsideTap] = useState(false);

  const handleSheetChanges = (index: number) => {
    if (index === -1) {
      setCurrentSnapPosition('hidden');
    } else {
      setCurrentSnapPosition('54%');
    }
  };


  useEffect(() => {
      const showSub = Keyboard.addListener('keyboardDidShow', () => {
        if (
          !modalClosedByOutsideTap &&
          currentSnapPosition !== '90%' &&
          currentSnapPosition !== 'hidden'
        ) {
          addSheetRef.current?.snapToPosition('90%', { duration: 150 });
          setCurrentSnapPosition('90%');
        }
      });
  
      const hideSub = Keyboard.addListener('keyboardDidHide', () => {
        setModalClosedByOutsideTap(false);
        if (currentSnapPosition === '90%') {
          addSheetRef.current?.snapToPosition('54%', { duration: 150 });
          setCurrentSnapPosition('54%');
        }
      });
  
      return () => {
        showSub.remove();
        hideSub.remove();
      };
    }, [currentSnapPosition, modalClosedByOutsideTap]);

  return (
    <TouchableWithoutFeedback onPress={() => {
              Keyboard.dismiss();
              addSheetRef.current?.close();
              setCurrentSnapPosition('hidden');
            }} accessible={false}>
      <View className="flex-1">
        <Stack>
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="inbox/[message]" options={{
            headerShown: true,
            title: "Message",
            headerStyle: {
              backgroundColor: '#2563eb'
            },
            headerTintColor: '#fff',
            headerTitleStyle: {
              fontWeight: 'bold',
              fontSize: 18,
            },
            headerBackTitle: 'Inbox'
          }} />
        </Stack>
        <BottomSheet
          ref={bottomSheetRef}
          index={-1}
          snapPoints={['54%']}
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
          <View className="px-5 py-4 bg-cardColor">
            <Text className="text-xl font-bold text-main mb-4">Select Term</Text>
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
          enableOverDrag={false}
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
               <Text className="text-xl text-main font-bold mb-4">Add New Assignment</Text>
                <View className="mb-5">
                  <Text className="text-sm font-semibold text-main mb-1">Assignment Name</Text>
                  <TextInput
                    className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                    onChangeText={(i) => {
                      setName(i);
                    }}
                    value={name}
                    editable
                    placeholder="Assignment Name"
                  />
                </View>
                <View className="mb-5">
                  <Text className="text-sm font-semibold text-main mb-1">Category</Text>
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


                <View className="h-[1px] bg-accent opacity-20 mb-5" />

                <View className="mb-5">
                  <Text className="text-sm font-semibold text-main mb-1">Grade</Text>
                  <TextInput
                    className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                    placeholder="Enter grade"
                    keyboardType="numeric"
                    value={grade.toString()}
                    onChangeText={(i) => {
                      setGrade(Number(i));
                    }}
                  />
                </View>

                <View className="mb-6">
                  <Text className="text-sm font-semibold text-main mb-1">Out Of</Text>
                  <TextInput
                    className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                    placeholder="Enter total"
                    keyboardType="numeric"
                    value={outOf.toString()}
                    onChangeText={(i) => {
                      setOutOf(Number(i));
                    }}
                  />
                </View>
                <TouchableOpacity
                  onPress={onSubmit}
                  className="bg-highlight rounded-md py-3">
                  <Text className="text-center text-highlightText font-bold text-lg">Add Assignment</Text>
                </TouchableOpacity>
              </BottomSheetView>
            </TouchableWithoutFeedback>
        </BottomSheet>
        </View>
      </TouchableWithoutFeedback>
  );
}

export default function RootLayout() {
  return (
    <AddSheetProvider>
      <BottomSheetProvider>
        <BottomSheetModalProvider>
          
            <GestureHandlerRootView style={{ flex: 1 }}>
              
                <InnerLayout />
            </GestureHandlerRootView>
          
        </BottomSheetModalProvider>
      </BottomSheetProvider>
      </AddSheetProvider>
    )
}
