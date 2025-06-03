import React, { useState, useEffect } from 'react';
import { View, TextInput, Button, Text, ScrollView, TouchableOpacity } from 'react-native';
import * as SecureStore from 'expo-secure-store';
import { Image } from 'react-native'
import { icons } from "@/constants/icons";

const STORAGE_KEY = 'person_info';

export default function PersonInfoScreen() {
  const [name, setName] = useState('');
  const [link, setLink] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    (async () => {
      const data = await SecureStore.getItemAsync(STORAGE_KEY);
      if (data) {
        const parsed = JSON.parse(data);
        setName(parsed.name);
        setLink(parsed.link);
        setUsername(parsed.username);
        setPassword(parsed.password);
      }
    })();
  }, []);

  const saveInfo = async () => {
    const data = { name, link, username, password };
    await SecureStore.setItemAsync(STORAGE_KEY, JSON.stringify(data));
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  return (
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
  );
}