import { View, Text } from 'react-native'
import React from 'react'

const inbox = () => {
  return (
    <View className='bg-primary flex-1'>
        <View className="bg-blue-600 pt-14 pb-4 px-5">
            <Text className="text-white text-3xl font-bold">Inbox</Text>
        </View>
      <Text>inbox</Text>
    </View>
  )
}

export default inbox