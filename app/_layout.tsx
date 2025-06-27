import { useColorScheme, TouchableOpacity, Text, LayoutAnimation, View } from "react-native";
import { Ionicons } from '@expo/vector-icons';
import { BottomSheetProvider, useBottomSheet, TermLabel } from "@/context/BottomSheetContext";
import BottomSheet, { BottomSheetModalProvider, BottomSheetBackdrop, BottomSheetFlatList } from "@gorhom/bottom-sheet";
import { colors } from "@/utils/colorTheme";
import { Stack } from "expo-router";
import './globals.css';
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { useEffect } from "react";
import Animated, { useSharedValue, useAnimatedStyle, withTiming } from 'react-native-reanimated';


const terms: TermLabel[] = ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades'];

function InnerLayout() {
  const { selectedCategory, setSelectedCategory, bottomSheetRef } = useBottomSheet();
  const colorScheme = useColorScheme();
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light;


  return (
      <>
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
          snapPoints={['53%']}
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
      </>
  );
}

export default function RootLayout() {
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
