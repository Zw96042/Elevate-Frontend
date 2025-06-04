import { View, Text, FlatList } from 'react-native'
import React from 'react'
import MessageCard from '@/components/MessageCard';

const MESSAGES = [
  {
    className: "AP Pre Cal",
    subject: "Sports Registration",
    from: "Mr ABC",
    date: "01-02-2025",
    content: "Enim tempor in tempor culpa commodo qui do. Dolore duis pariatur in labore. Exercitation deserunt nostrud laborum incididunt excepteur magna esse id. Officia excepteur magna dolor ex do laboris irure elit aliquip."
  },
  {
    className: "AP BIO",
    subject: "Dropped Lowest Grade",
    from: "Mr ABC",
    date: "01-04-2025",
    content: "In laborum nostrud adipisicing aliqua commodo aliqua nostrud officia magna laborum consectetur exercitation ullamco. Magna esse exercitation commodo culpa adipisicing. Aute et deserunt veniam do enim. Ea velit nulla veniam exercitation aliqua cupidatat incididunt proident non sint quis dolore. Cillum in sit est labore duis ad sunt excepteur sunt non qui non Lorem deserunt. Aute ex ad ipsum est fugiat voluptate cillum ipsum velit duis ad veniam sint."
  },
  {
    className: "AP Human Geo",
    subject: "Semester 1, AP Calc BC",
    from: "Mr ABC",
    date: "01-10-2025",
    content: "Qui incididunt irure nulla cillum fugiat deserunt consectetur mollit eiusmod elit. Ex ut sunt consectetur nisi commodo et anim reprehenderit. Proident id sunt aute officia. In proident quis velit do deserunt officia consequat. Sunt adipisicing sint Lorem aliquip. Reprehenderit in consectetur eiusmod irure irure ea deserunt deserunt. Ex officia sunt commodo occaecat sint enim ullamco."
  }
];

const sortedMessages = MESSAGES.sort(
  (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime()
);

const inbox = () => {
  return (
    <View className='bg-primary flex-1'>
        <View className="bg-blue-600 pt-14 pb-4 px-5">
            <Text className="text-white text-3xl font-bold">Inbox</Text>
        </View>
      <FlatList
      className='mt-4 px-5'
      data={sortedMessages}
      renderItem={({ item }) => (
        <MessageCard 
        subject={item.subject}
        className={item.className}
        from={item.from}
        date={item.date}
        content={item.content}
        />
      )}
      keyExtractor={(item) => item.subject.toString()}
      ItemSeparatorComponent={() => <View className="h-4" />}
      />
    </View>
  )
}

export default inbox