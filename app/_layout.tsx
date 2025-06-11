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

/*
const DATA = [
  {
    name: 'BIOLOGY_1_HONORS',
    teacher: 'MARISA_SPEARS',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [85, 95, 75]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'AP_PRECALCULUS',
    teacher: 'KENZIE_SANCHEZ',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'AP_HUMAN_GEOGRAPHY',
    teacher: 'IAN_FULLMER',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'INVENTION_&_INNOVATION_FF',
    teacher: 'NORMAN_MORGAN',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 85
    },
  },
  {
    name: 'WATER_POLO_B_1',
    teacher: 'DARCI_CARRUTHERS',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'ENGLISH_1_HONORS',
    teacher: 'CATHERINE_KELLY',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'AP_COMPUTER_SCIENCE_A_Math',
    teacher: 'ISIANA_RENDON',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
];
*/