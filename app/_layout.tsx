import { Stack } from "expo-router";
import './globals.css';
import { GestureHandlerRootView } from "react-native-gesture-handler";

export default function RootLayout() {
  return <GestureHandlerRootView style={{ flex: 1 }}>
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
  </GestureHandlerRootView>;
}
