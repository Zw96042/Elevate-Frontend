import { useColorScheme, TouchableOpacity, View, Text } from "react-native";
import { BottomSheetProvider, useBottomSheet, TermLabel } from "@/context/BottomSheetContext";
import BottomSheet, { BottomSheetModalProvider, BottomSheetBackdrop, BottomSheetFlatList } from "@gorhom/bottom-sheet";
import { Ionicons } from "@expo/vector-icons";
import { colors } from "@/utils/colorTheme";
import { Stack } from "expo-router";
import './globals.css';
import { GestureHandlerRootView } from "react-native-gesture-handler";


const terms: TermLabel[] = ['Q1 Grades', 'Q2 Grades', 'SM1 Grade', 'Q3 Grades', 'Q4 Grades', 'SM2 Grades'];

function InnerLayout() {
  const { selectedCategory, setSelectedCategory, bottomSheetRef } = useBottomSheet();
  const colorScheme = useColorScheme();
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light

  return (
    <>
      <Stack>
        <Stack.Screen name="(tabs)" options={{headerShown: false}}/>
        <Stack.Screen name="classes/[class]" options={{headerShown: false}}/>
        <Stack.Screen name="assignments/[assignment]" options={{headerShown: false}}/>
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
        }}/>
      </Stack>
      <BottomSheet
        ref={bottomSheetRef}
        index={-1}
        snapPoints={['42%']}
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
       <BottomSheetFlatList
          data={terms}
          keyExtractor={(item) => item}
          renderItem={({ item }) => (
            <TouchableOpacity
              onPress={() => {
                setSelectedCategory(item);
                bottomSheetRef.current?.close();
              }}
              className="px-5 py-4"
            >
              <Text className="text-main text-lg">{item}</Text>
            </TouchableOpacity>
          )}
          scrollEnabled={false}
          className={'bg-cardColor'}
        />
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

