import React, { useState, useEffect } from 'react';
import { View, TextInput, Button, Text, ScrollView, TouchableOpacity, TouchableWithoutFeedback, Keyboard, KeyboardAvoidingViewComponent, KeyboardAvoidingView, Platform } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Image } from 'react-native'
import { icons } from "@/constants/icons";
import { authenticate } from '@/lib/authHandler';

const STORAGE_KEY = 'person_info';

export default function PersonInfoScreen() {
  const [name, setName] = useState('');
  const [link, setLink] = useState('');

  const [saved, setSaved] = useState(false);

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

useEffect(() => {
  const loadInfo = async () => {
    const storedName = await AsyncStorage.getItem('person_info_name');
    const storedLink = await AsyncStorage.getItem('skywardLink');
    const storedUser = await AsyncStorage.getItem('skywardUser');
    const storedPass = await AsyncStorage.getItem('skywardPass');

    if (storedName) setName(storedName);
    if (storedLink) setLink(storedLink);
    if (storedUser) setUsername(storedUser);
    if (storedPass) setPassword(storedPass);
  };

  loadInfo();
}, []);

const saveInfo = async () => {
  try {
    await AsyncStorage.setItem('person_info_name', name);
    await AsyncStorage.setItem('skywardUser', username);
    await AsyncStorage.setItem('skywardPass', password);
    await AsyncStorage.setItem('skywardLink', link);

    console.log("Saved credentials:");
    console.log("skywardLink:", link);
    console.log("skywardUser:", username);
    console.log("skywardPass:", password);

    setSaved(true);
    setTimeout(() => setSaved(false), 2000);

    // Now authenticate with saved credentials
    const authResult = await authenticate();

    if (authResult.success) {
      console.log("Authentication succeeded");
      // Optionally: store session codes here or show UI feedback
    } else {
      console.error("Authentication failed:", authResult.error);
      // Optionally: show user error feedback
    }
  } catch (error) {
    console.error("Failed to save credentials", error);
  }
};

  return (
    <KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : "height"} className='flex-1 bg-primary'>
      <TouchableWithoutFeedback onPress={Keyboard.dismiss}>
        <View className='flex-1 bg-primary'>
            <View className="bg-blue-600 pt-14 pb-4 px-5">
                <Text className="text-white text-3xl font-bold">Settings</Text>
            </View>
            <View className='flex-1 p-10'>
                <View className=' bg-slate-800 w-full h-[29rem] rounded-3xl'>
                    <View className='flex-1 px-4 pb-10'>
                            <View className='bg-[#3b5795] self-start rounded-xl mt-3 ml-auto'>
                                <TouchableOpacity onPress={saveInfo} className="w-full">
                                    <Text className='font-bold text-sm text-[#7398e6] p-1 text-center'>Save Info</Text>
                                </TouchableOpacity>
                            </View>
                            <View className="mb-4 ">
                                <Text className="text-lg font-semibold mb-2 text-white">Name</Text>
                                <TextInput
                                className="border border-[#cbd5e1] rounded-lg p-3 text-white"
                                value={name}
                                onChangeText={setName}
                                placeholder="Name"
                                />
                            </View>

                            <View className="mb-4">
                                <Text className="text-lg font-semibold mb-2 text-white">Skyward Link</Text>
                                <TextInput
                                className="border border-[#cbd5e1] rounded-lg p-3 text-white"
                                value={link}
                                onChangeText={setLink}
                                placeholder="https://example.com"
                                autoCapitalize="none"
                                />
                            </View>

                            <View className="mb-4">
                                <Text className="text-lg font-semibold mb-2 text-white">Username</Text>
                                <TextInput
                                className="border border-[#cbd5e1] rounded-lg p-3 text-white"
                                value={username}
                                onChangeText={setUsername}
                                placeholder="Username"
                                autoCapitalize="none"
                                />
                            </View>

                            <View className="mb-4">
                                <Text className="text-lg font-semibold mb-2 text-white">Password</Text>
                                <TextInput
                                className="border border-[#cbd5e1] rounded-lg p-3 text-white"
                                value={password}
                                onChangeText={setPassword}
                                placeholder="Password"
                                secureTextEntry
                                />
                            </View>

                            

                            {saved && (
                                <Text className="text-green-600 mt-1 text-center">Saved successfully!</Text>
                            )}
                    </View>
                </View>
            </View>
          </View>
        </TouchableWithoutFeedback>
      </KeyboardAvoidingView>
  );
}