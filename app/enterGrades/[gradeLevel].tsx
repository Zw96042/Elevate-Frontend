import { Stack, useLocalSearchParams } from 'expo-router';
import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { View, Text, TouchableOpacity, Keyboard, TextInput, TouchableWithoutFeedback, DeviceEventEmitter, FlatList } from 'react-native';
import BottomSheet, { BottomSheetBackdrop, BottomSheetView } from '@gorhom/bottom-sheet';
import { useColorScheme } from 'nativewind';
import { toast } from 'burnt';
import { colors } from '@/utils/colorTheme';
import { AddClassSheetProvider, useAddClassSheet } from "@/context/AddClassSheetContext";
import AsyncStorage from '@react-native-async-storage/async-storage';
import ClassCard2Sem from '@/components/ClassCard2Sem';
import { MotiView } from 'moti';
import { AnimatePresence } from 'moti';
import { Easing } from 'react-native-reanimated';
import { ScrollView, Swipeable } from 'react-native-gesture-handler';

const availableClasses = [
  "INTEGRATED PHYSICS AND CHEMISTRY MODIFIED - SE300 ( IPC)",
  "3D CAD ENGINEERING DESIGN AND PRESENTATION - TC350 (ENGDSPR)",
  "3D MODELING & ANIMATION - 700B (TA3DMA)",
  "ACCOUNTING - TC660 (ACCOUNT1)",
  "ADAPTIVE PHYSICAL EDUCATION",
  "ADVERTISING - TC654 (ADVSALPR)",
  "ALGEBRA ALTERNATE - SE927 (ALG1)",
  "ALGEBRA I - MA224 (ALG1)",
  "ALGEBRA I HONORS  -  MA223 (ALG1)",
  "ALGEBRA I MODIFIED - SE225 (ALG 1)",
  "ALGEBRA II - MA245 (ALG 2)",
  "ALGEBRA II ALTERNATE - SE241 (ALG2)",
  "ALGEBRA II HONORS - MA240 (ALG2)",
  "AMERICAN SIGN LANGUAGE I - FL642 (ASL1)",
  "AMERICAN SIGN LANGUAGE II - FL643 (ASL2)",
  "AMERICAN SIGN LANGUAGE III HONORS - FL645H",
  "AMERICAN SIGN LANGUAGE IV HONORS - FL641H",
  "ANATOMY AND PHYSIOLOGY(Honors) - SC340 (ANAT&PHY)",
  "ANCIENT CIVILIZATIONS - SS418A/B",
  "AP 2-D ART AND DESIGN - VA009 (AP2DDP)",
  "AP 3D ART AND DESIGN (CERAMICS) - VA010 (AP3DDP)",
  "AP 3D ART AND DESIGN (SCULPTURE) - VA008 (AP3DDP)",
  "AP ART HISTORY - VA029 (APHISART)",
  "AP BIOLOGY - SC315 (AP-BIO)",
  "AP CALCULUS AB - MA266 (APCALCAB)",
  "AP CALCULUS BC - MA267 (APCALCBC)",
  "AP CAPSTONE RESEARCH - LA143 (APRES)",
  "AP CAPSTONE SEMINAR - LA142 (APSMNR)",
  "AP CHEMISTRY - SC325 (AP-CHEM)",
  "AP CHINESE LANGUAGE AND CULTURE (LEVEL IV) - FL 649 (APCHLAN)",
  "AP COMPARATIVE GOVERNMENT - SS426",
  "AP COMPUTER SCIENCE A: MA281 (APTACSA)",
  "AP COMPUTER SCIENCE PRINCIPLES - TC736 (PRINIT)",
  "AP DRAWING - VA011 (APSTARTD)",
  "AP ENGLISH LITERATURE AND COMPOSITION (AP ENGLISH IV) - LA126A (APENGLIT)",
  "AP ENVIRONMENTAL SCIENCE - SC341 (AP-ENVIR)",
  "AP EUROPEAN HISTORY - SS452 (APEUHIST)",
  "AP FRENCH LANGUAGE AND CULTURE (LEVEL IV) - FL606 (APFRLAN)",
  "AP HUMAN GEOGRAPHY - SS403 (APHUMGEO)",
  "AP LANGUAGE AND COMPOSITION (AP ENGLISH III) - LA118 (APENGLAN)",
  "AP LATIN (LEVEL IV) - FL625 (APLATVG)",
  "AP MACROECONOMICS - SS430 (APMACECO)",
  "AP MICROECONOMICS - SS431 (APMICECO)",
  "AP PHYSICS 1 - SC332 (APPHYS1)",
  "AP PHYSICS 2 - SC333 (APPHYS2)",
  "AP PHYSICS C - SC334 (APPHYSCE and APPHYSCM)",
  "AP PHYSICS I & 2 - SC335 (APPHYS1 and APPHYS2)",
  "AP PRECALCULUS - MA259",
  "AP PSYCHOLOGY  - SS437 (APPSYCH)",
  "AP SPANISH IV - FL638 (APSPALAN)",
  "AP SPANISH V - FL639 (APSPALIT)",
  "AP STATISTICS - MA262 (APSTATS)",
  "AP UNITED STATES GOVERNMENT - SS420 (APUSGOVT)",
  "AP UNITED STATES HISTORY - SS410 (APUSHIST)",
  "AP WORLD HISTORY - SS402 (APWHIST)",
  "APPLIED MUSIC",
  "ARCHITECTURE AND INTERIOR DESIGN - TC714 (INTERDSN)",
  "ART HISTORICAL METHODS - VA036 (HUMANIT2)",
  "ART HISTORICAL METHODS II - VA037 (RESHUM)",
  "ART I: ART AND MEDIA COMMUNICATIONS - VA023 (ART1MCOM)",
  "ART I: Foundations of Art with Emphasis on Painting and Drawing -- VA001 (ART1)",
  "ART I: Foundations of Art with Emphasis on Sculpture and Ceramics -- VA001B (ART1)",
  "ART II: CERAMICS - VA013 (ART2CRMC)",
  "ART II: DIGITAL ART AND MEDIA - VA025 (ART2EM)",
  "ART II: DIMENSIONAL DESIGN & SCULPTURE 1 - VA002 (ART2SCLP)",
  "ART II: STUDIO PAINTING & DRAWING - VA003 (ART2DRAW)",
  "ART II: STUDIO PHOTOGRAPHY - VA035 (ART2PHTO)",
  "ART III: CERAMICS - VA015 (ART3CRMC)",
  "ART III: DIGITAL ART AND MEDIA - VA026 (ART3EM)",
  "ART III: SCULPTURE - VA031 (ART3SCLP)",
  "ART III: STUDIO DRAWING - VA004 (ART3DRAW)",
  "ART III: STUDIO PAINTING - VA006 (ART3PATG)",
  "ART IV: CERAMICS - VA017 (ART4CRMC)",
  "ART IV: DIGITAL ART AND MEDIA - VA028 (ART4EM)",
  "ART IV: SCULPTURE - VA034 (ART4SCLP)",
  "ART IV—DRAWING / PAINTING III - VA011G (ART4DRAW)",
  "ASTRONOMY - SC351 (ASTRMY)",
  "ATHLETIC TRAINING - SPORTS MEDICINE (SPORTMD1, SPORTMD2, SPORTMD3)",
  "BASEBALL",
  "BASKETBALL Boys",
  "BASKETBALL Boys 9th Grade AT833A/B*",
  "BASKETBALL Girls",
  "BASKETBALL Girls 9th Grade - AT831A/B*",
  "BEGINNING GUITAR - PA550 (MUS1GTR)",
  "BIOLOGY ALTERNATE - SE313 (BIO)",
  "BIOLOGY I - SC310 (BIO)",
  "BIOLOGY I HONORS - SC311 (BIO)",
  "BIOLOGY MODIFIED - SE310 (BIO)",
  "BIOTECHNOLOGY - SC316 (ADVBIOT)",
  "BUSINESS ACCELeratoredu - TC468 (BUSMGT )",
  "BUSINESS INCUBATOR - TC467 (ENTREP)",
  "BUSINESS INFORMATION MANAGEMENT - TC741 (BUSIM1)",
  "BUSINESS LAW - TC670A (BUSLAW)",
  "CALCULUS - MA251 (INSTUMTH)",
  "CAREER PREPARATION",
  "CERT: DISASTER RESPONSE - TC772 (DISRESP)",
  "CERT: DISASTER RESPONSE II - TC772B",
  "CHAMBER ORCHESTRA B (Cello and Bass) - PA632 (MUS1ORCH)",
  "CHAMBER ORCHESTRA T (Violin and Viola) - PA631 (MUS1ORCH)",
  "CHAPARRAL TENOR/BASS",
  "CHAPARRAL TREBLE",
  "CHEERLEADER",
  "CHEMISTRY I  - SC320 (CHEM)",
  "CHEMISTRY I HONORS - SC321 (CHEM)",
  "Chemistry Modified - SE322",
  "CHILD DEVELOPMENT - TC710 (CHILD-DEV)",
  "CHINESE 5/6 ADVANCED - FL650/FL651 (CHIN 5/CHIN 6)",
  "CHINESE I - FL646 (CHIN1)",
  "CHINESE II - FL647 (CHIN2)",
  "CHINESE III HONORS - FL648 (CHIN3)",
  "COMPUTER SCIENCE II  - TC285 (TACS2)",
  "COMPUTER SCIENCE III - TC737 (TACS3)",
  "COMPUTER SCIENCE INDEPENDENT STUDY - TC738 (TAIND2)",
  "CONCERT BAND",
  "CONCERT TENOR/BASS (9th - PA671, 10th - PA673)",
  "CONCERT TREBLE (9th - PA670, 10th - PA672)",
  "CREATIVE WRITING I - LA136 (CREAT WR)",
  "CREATIVE WRITING II - LA137 (CREAT WR)",
  "CROSS COUNTRY Boys",
  "CROSS COUNTRY Girls",
  "DANCE",
  "DEBATE I - LA500 (DEBATE 1)",
  "DEBATE II - LA502 (DEBATE 2)",
  "DEBATE III - LA503 (DEBATE 3)",
  "DIGITAL GRAPHICS AND ANIMATION I - TC701 (TADGA)",
  "DIGITAL GRAPHICS and ANIMATION II - TC703 (GRAPHDI)",
  "EARTH SYSTEMS SCIENCE  - SC346 (ESS)",
  "ECONOMICS - SS435 (ECO-FE)",
  "ECONOMICS ALTERNATE - SE438 (ECO)",
  "ECONOMICS MODIFIED - SE435 (ECO)",
  "EDITORIAL LEADERSHIP I, II, & III",
  "ELITE VISUAL ENSEMBLE (EVE)",
  "ENGINEERING - SC350 (SCITECH)",
  "ENGLISH I - LA106 (ENG1)",
  "ENGLISH I ALTERNATE - SE141 (ENG 1)",
  "ENGLISH I HONORS - LA102 (ENG 1)",
  "ENGLISH I MODIFIED - SE106 (ENG1)",
  "ENGLISH II - LA114 (ENG 2)",
  "ENGLISH II ALTERNATE - SE142 (ENG2)",
  "ENGLISH II HONORS - LA117 (ENG 2)",
  "ENGLISH II MODIFIED - SE114 (ENG2)",
  "ENGLISH III - LA122 (ENG 3)",
  "ENGLISH III ALTERNATE - SE143 (ENG 3)",
  "ENGLISH III MODIFIED - SE122 (ENG3)",
  "ENGLISH IV - LA132 (ENG 4)",
  "ENGLISH IV ALTERNATE - SE144 (ENG 4)",
  "ENGLISH IV MODIFIED - SE132 (ENG4)",
  "ENVIRONMENTAL SYSTEMS - SC342 (ENVIRSYS)",
  "EPICURE ACADEMY—CULINARY ARTS - TC717 (INCULART)",
  "EXCUSED PERIOD",
  "FASHION DESIGN - TC712 (FASHDSN)",
  "FILM 1 - FILM PRODUCTION - TC775 (TADGVAD)",
  "FILM 2 - ADVANCED FILM PRODUCTION - TC774 (AVPROD)",
  "FILM 3 - ADVANCED FILM PORTFOLIO - TC102 (PROBS3)",
  "FILM 4 - FILM MENTORSHIP - TC466T (PROBS2)",
  "FILM 4 - PRACTICUM IN FILM PRODUCTION - TC778 (PRACAVT)",
  "FINE ARTS MAGAZINE: THE FINAL DRAFT - LA193 (LM1)",
  "FOOD PREPARATION AND NUTRITION - TC716 (LNURTWEL)",
  "FOOD SCIENCE MODIFIED - SE315 (Food Science Mod)",
  "FOOTBALL",
  "FOOTBALL 9th Grade - AT832A/B*",
  "FRENCH 5/6 ADVANCED ~ FL607/FL608 (FREN 5/FREN 6)",
  "FRENCH I - FL600 (FREN1)",
  "FRENCH II - FL601 (FREN2)",
  "FRENCH III HONORS - FL604 (FREN3)",
  "GEOMETRY - MA235 (GEOM)",
  "GEOMETRY ALTERNATE - SE240 (GEOM)",
  "GEOMETRY HONORS - MA230 (GEOM)",
  "GEOMETRY MODIFIED - SE227 (GEOM)",
  "GOLF Boys",
  "GOLF Girls",
  "GOVERNMENT ALTERNATE - SE437 (GOVT)",
  "HARP ENSEMBLE",
  "HEALTH EDUCATION - PE800 (HLTH ED)",
  "HEALTH EDUCATION MODIFIED - SE823 (HLTH)",
  "HEALTH SCIENCE CLINICAL - TC769 (HLTHSCI)",
  "HISTORY OF ROCK & ROLL - SS451 (SPTSS)",
  "HYLINE",
  "INDEPENDENT JOURNALISM - LA192 (IND JOUR)",
  "INDEPENDENT STUDY IN ENGLISH - LA145 (IND ENG)",
  "INDEPENDENT STUDY IN SPEECH - LA511 (IND SPCH)",
  "INTEGRATED PHYSICS & CHEMISTRY ALTERNATE - SE314 (IPC)",
  "INTEGRATED PHYSICS AND CHEMISTRY - SC301 (IPC)",
  "INVENTION AND INNOVATION: FIRST FOCUS PRINCIPLES OF APPLIED ENGINEERING AND TECH - TC354C (PRAPPENG)",
  "JAZZ ENSEMBLE",
  "JOURNALISM",
  "KINESIOLOGY - TC031 (KINES1)",
  "KINESIOLOGY II - TC033",
  "LATIN I - FL620 (LATIN1)",
  "LATIN II - FL621 (LATIN2)",
  "LATIN III HONORS - FL624 (LATIN3)",
  "LATIN V ADVANCED - FL626 (LATIN 5)",
  "LATIN VI ADVANCED - FL627 (LATIN6)",
  "LINEAR ALGEBRA - MA269 (LINALG)",
  "MATHEMATICAL MODELS WITH APPLICATIONS - MA227 (MTHMOD)",
  "MEDICAL TERMINOLOGY - TC771A (MEDTERM)",
  "MENTORSHIP - TC466A (PROBS1)",
  "METHODOLOGY FOR ACADEMIC AND PERSONAL SUCCESS I - EL 113 (MAPS I)",
  "MODEL UNITED NATIONS - (SPTSS)",
  "MODERN PHYSICS - SC337",
  "MULTIVARIABLE CALCULUS - MA268 (MUTLCAL)",
  "MUSIC THEORY AP - PA563 (APMUSTHY)",
  "NEWS MEDIA I - LA170 (NP1)",
  "NEWS MEDIA II - LA174 (NP2)",
  "NEWS MEDIA III - LA178 (NP3)",
  "OFFICE AIDE - BE672 (LC SC SU)",
  "ORAL INTERPRETATION I - LA512 (ORALINT1)",
  "ORAL INTERPRETATION II - LA513 (ORALINT2)",
  "ORAL INTERPRETATION III - LA516 (ORALINT3)",
  "ORGANIC CHEMISTRY - SC352 (ORGCHEM)",
  "OUTDOOR  EDUCATION - PE802 - (Lifetime Recreation and Outdoor Pursuits)",
  "PATH to College and Career (PATHCC1)",
  "PATH to College and Career ALT",
  "PE YOGA - PE801 (Lifetime Fitness and Wellness Pursuits)",
  "PE: Personal Fitness and Team Sports - PE803A/B (Skill-Based Lifetime Activities)",
  "PEER PARTNERS",
  "PERSONAL FINANCE I - SE201 (MTHMOD)",
  "PERSONAL FINANCIAL LITERACY AND ECONOMICS- SS467 (PFLECO)",
  "PERSONAL HEALTH/HYGIENE ALTERNATE - SE990 (HLTH)",
  "PHILHARMONIC ORCHESTRA",
  "PHOTOJOURNALISM A - LA180 (PHOTJOUR)",
  "PHOTOJOURNALISM B - LA182 (PHOTJOUR)",
  "PHYSICS I - SC331 (PHYSICS)",
  "PRACTICUM IN HEALTH SCIENCE-PHARMACY TECHNICIAN - TC777 (PRACHLSC)",
  "PRACTICUM IN HEALTH SCIENCE-PHLEBOTOMY TECHNICIAN - TC783 (PRACHLS2)",
  "PRECALCULUS - MA252 (PRECALC)",
  "PRINCIPLES OF APPLIED ENGINEERING AND TECH - TC354 (PRAPPENG)",
  "PRINCIPLES OF BUSINESS, MARKETING AND FINANCE - TC651A (PRINBMF)",
  "PRINCIPLES OF HEALTH SCIENCE - TC770 (PRINHLSC)",
  "PSYCHOLOGY I - SS440 (PSYCH)",
  "READING IMPROVEMENT - SE120 (READ)",
  "READING IMPROVEMENT ALTERNATE",
  "READING IMPROVEMENT I - LA135 (READ 1)",
  "READING SEMINAR",
  "ROBOTICS ENGINEERING — FIRST FOCUS - TC355 (ROBOTIC1)",
  "ROBOTICS III - SC356 (SCI/R&D2)",
  "ROBOTICS II - TC357 (ROBOTIC2)",
  "SOCCER Boys",
  "SOCCER Girls",
  "SOCIAL MEDIA MARKETING TC654B",
  "SOCIOLOGY - SS445 (SOC)",
  "SOFTBALL Girls",
  "SPANISH I - FL630 (SPAN1)",
  "SPANISH II - FL631 (SPAN2)",
  "SPANISH III - FL635 (SPAN3)",
  "SPANISH III HONORS - FL634 (SPAN3)",
  "SPANISH IV - FL637 (SPAN4)",
  "SPANISH V - FL636 (SPAN5)",
  "SPANISH VI Advanced (FL640)",
  "STAR STEPPERS",
  "STATISTICS - MA261 (STATS)",
  "STATS 2: BEYOND AP STATISTICS - MA270 (INSTMTH2)",
  "STUDENT COUNCIL/LEADERSHIP - SS464 (STULEAD)",
  "SWIFT CODING - TC280 (TACSI)",
  "SWIMMING/DIVING",
  "SYMPHONIC BAND",
  "SYMPHONY ORCHESTRA A",
  "SYMPHONY ORCHESTRA B",
  "TECHNICAL THEATRE I - PA520 (TH1TECH)",
  "TECHNICAL THEATRE II - PA522 (TH2TECH)",
  "TECHNICAL THEATRE III - PA528 (TH3TECH)",
  "TECHNICAL THEATRE PRODUCTION I - PA526 (TH1PROD)",
  "TECHNICAL THEATRE PRODUCTION II - PA527 (TH2PROD)",
  "TEEN TEACHING I - TC460",
  "TEEN TEACHING II - TC461 (FAMCOSRV)",
  "TENNIS JUNIOR VARSITY",
  "TENNIS VARSITY",
  "THEATRE ARTS I  - PA516 (TH1)",
  "THEATRE ARTS II - PA517 (TH2)",
  "THEATRE ARTS III - PA519 (TH3)",
  "THEATRE ARTS IV - PA515 (TH4)",
  "THEORY OF HEALTH SCIENCE - TC773 - (HLTHSCI)",
  "TRACK Boys",
  "TRACK Girls",
  "UNITED STATES GOVERNMENT - SS425 (GOVT)",
  "UNITED STATES HISTORY - SS415 (US HIST)",
  "US GOVERNMENT MODIFIED - SE425 (GOVT)",
  "US HISTORY ALTERNATE - SE453 (USHIST)",
  "US HISTORY MODIFIED - SE408 (USHIST)",
  "VARSITY TENOR/BASS CHORALE (11th - PA675, 12th - PA675D)",
  "VARSITY TREBLE CHORALE (11th - PA676, 12th - PA676D)",
  "VIDEO GAME DESIGN - TC707 (VIDEOGD)",
  "VIDEO PRODUCTION FOR SOCIAL MEDIA/CHAP RECAP - TC785 (TADGC)",
  "VIRTUAL BUSINESS - TC655 (VIRTBUS)",
  "VOLLEYBALL",
  "VOLLEYBALL Girls 9th Grade - AT830A/B*",
  "WATER POLO Boys",
  "WATER POLO Girls",
  "WIND ENSEMBLE",
  "WORLD GEOGRAPHY - SS400 (W GEO)",
  "WORLD GEOGRAPHY ALTERNATE - SE451 (WGEO)",
  "WORLD GEOGRAPHY MODIFIED - SE401 (W GEO)",
  "WORLD HISTORY - SS405 (WHIST)",
  "WORLD HISTORY ALTERNATE - SE452 (WHIST)",
  "WORLD HISTORY MODIFIED - SE406 (W HIST)",
  "WRESTLING Boys",
  "WRESTLING Girls",
  "YEARBOOK I - LA152 (YBK1)",
  "YEARBOOK II - LA156 (YBK2)",
  "YEARBOOK III - LA160 (YBK3)"
];

/*
JS to get class names:
(() => {
  const xpath = '//*[@id="fsEl_13310"]/div/div';
  const result = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
  const container = result.singleNodeValue;
  
  if (!container) {
    console.error('Container not found');
    return;
  }

  const articles = container.querySelectorAll('article');
  const classes = [];
  
  articles.forEach(article => {
    const anchor = article.querySelector('a.fsPostLink');
    if (anchor) {
      classes.push(anchor.textContent.trim());
    }
  });

  console.log(classes);
  return classes;
})();

Website: https://whs.eanesisd.net/coursecatalog/courses/all-courses
*/

type SavedClass = {
  className: string;
  sm1: number;
  sm2: number;
  teacher?: string;
};

const EnterGrades = () => {
  const { gradeLevel } = useLocalSearchParams();

  const [currentSnapPosition, setCurrentSnapPosition] = useState<'hidden' | '52%' | '100%' | '62%' | null>(null);
  const [modalClosedByOutsideTap, setModalClosedByOutsideTap] = useState(false);
  const { colorScheme } = useColorScheme();

  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light;

  const {
    addClassRef,
    name,
    setName,
    grade,
    setGrade,
    outOf,
    setOutOf,
    category,
    setCategory,
    // onSubmit, // remove this to override below
    categories
  } = useAddClassSheet();

  // SM1 grade input state and ref
  const gradeInputRef = React.useRef(null);
  const [sm1Value, setSm1Value] = React.useState(() =>
    !isNaN(Number(grade)) ? Number(grade).toFixed(2) : ''
  );

  const [classQuery, setClassQuery] = useState('');
  const [filteredClasses, setFilteredClasses] = useState<string[]>([]);

  const outOfInputRef = React.useRef(null);
  const [outOfValue, setOutOfValue] = React.useState(() =>
    !isNaN(Number(outOf)) ? Number(outOf).toFixed(2) : ''
  );

  const debounceRef = React.useRef<number | null>(null);

  const [savedClasses, setSavedClasses] = useState<SavedClass[]>([]);

  // State for selected semesters
  const [semesters, setSemesters] = useState<string[]>(['Fall Semester', 'Spring Semester']);

  // Memoized snapPoints for BottomSheet
  const snapPoints = useMemo(
    () => [semesters.length === 2 ? '62%' : '52%'],
    [semesters.length]
  );

  useEffect(() => {
    const loadSavedClasses = async () => {
      try {
        const stored = await AsyncStorage.getItem(`savedClasses-${gradeLevel}`);
        if (stored) {
          setSavedClasses(JSON.parse(stored));
        }
      } catch (e) {
        console.error('Failed to load saved classes', e);
      }
    };
    loadSavedClasses();
  }, []);

  const handleSheetChanges = (index: number) => {
    if (index === -1) {
      setCurrentSnapPosition('hidden');
    } else if (currentSnapPosition === null) {
      const snapValue = semesters.length === 2 ? '62%' : '52%';
      setCurrentSnapPosition(snapValue);
    } else {
      setCurrentSnapPosition('52%');
    }
  };

  useEffect(() => {
    const showSub = Keyboard.addListener('keyboardDidShow', () => {
      if (
        !modalClosedByOutsideTap &&
        currentSnapPosition !== '100%' &&
        (currentSnapPosition !== 'hidden' && currentSnapPosition !== null)
      ) {
        addClassRef.current?.snapToPosition('100%', { duration: 150 });
        setCurrentSnapPosition('100%');
      }
    });
    const hideSub = Keyboard.addListener('keyboardDidHide', () => {
      if (modalClosedByOutsideTap) {
        setModalClosedByOutsideTap(false);
        return;
      }
      if (currentSnapPosition === '100%') {
        const snapValue = semesters.length === 2 ? '62%' : '52%';
        addClassRef.current?.snapToPosition(snapValue, { duration: 150 });
        setCurrentSnapPosition(snapValue);
      }
    });
    return () => {
      showSub.remove();
      hideSub.remove();
    };
  }, [currentSnapPosition, modalClosedByOutsideTap, semesters.length]);

  const onSubmit = async () => {
    if (!name.trim()) {
      toast({
        title: 'Missing Info',
        message: 'Please provide all info',
        preset: 'error',
        duration: 1.2,
      });
      return;
    }

    if (semesters.length === 0) {
      toast({
        title: 'Missing Info',
        message: 'Select at least one semester',
        preset: 'error',
        duration: 1.2,
      });
      return;
    }

    const newClass: SavedClass & { semesters?: string[] } = {
      className: name.trim(),
      sm1: semesters.includes('Fall Semester') ? Number(sm1Value) : -1,
      sm2: semesters.includes('Spring Semester') ? Number(outOf) : -1,
      teacher: '',
      semesters,
    };

    try {
      const updatedClasses = [newClass, ...savedClasses.filter(c => c.className !== newClass.className)];
      setSavedClasses(updatedClasses);

      await AsyncStorage.setItem(`savedClasses-${gradeLevel}`, JSON.stringify(updatedClasses));
      
      toast({ title: 'Class added', preset: 'done', duration: 0.7 });
      setModalClosedByOutsideTap(true);
      Keyboard.dismiss();
      addClassRef.current?.close();
      setCurrentSnapPosition('hidden');
    } catch (e) {
      console.error('Error saving class', e);
    }
  };

  useEffect(() => {
    const sub = DeviceEventEmitter.addListener('classDeleted', async () => {
        const raw = await AsyncStorage.getItem(`savedClasses-${gradeLevel}`);
        setSavedClasses(raw ? JSON.parse(raw) : []);
    });

    return () => sub.remove();
    }, [gradeLevel]);

  return (
    <>
      <Stack.Screen
        options={{
        title: decodeURIComponent(gradeLevel.toString().concat(" year grades")),
        headerStyle: { backgroundColor: '#2563eb' },
        headerTintColor: '#fff',
        headerTitleStyle: {
            fontWeight: 'bold',
            fontSize: 18,
        },
        headerBackTitle: 'GPA',
        }}
      />
      <ScrollView className="flex-1 bg-primary">
        <View className='px-6'>
            <View className="bg-cardColor rounded-2xl p-6 border border-dashed border-highlightText shadow-md flex items-center justify-center space-y-4 mt-5">
                <Text className="text-main text-lg mb-3 text-center">
                    Add classes to create your {gradeLevel} year GPA history.
                </Text>
                <TouchableOpacity
                    activeOpacity={0.8}
                    className="bg-highlight px-6 py-2 rounded-full shadow-lg"
                    onPress={() => {
                      setModalClosedByOutsideTap(false);
                      const snapValue = semesters.length === 2 ? '62%' : '52%';
                      addClassRef.current?.snapToPosition(snapValue);
                      setCurrentSnapPosition(snapValue);
                    }}
                >
                    <Text className="text-highlightText font-semibold text-base text-center">
                        Add a class
                    </Text>
                </TouchableOpacity>
            </View>
        </View>
        <View className="w-full">
          {savedClasses.length > 0 && (
            <View className="mt-4 space-y-4 w-full">
              <AnimatePresence>
                {savedClasses.map((cls) => (
                  <MotiView
                    key={cls.className}
                    from={{ opacity: 1, translateX: 0 }}
                    animate={{ opacity: 1, translateX: 0 }}
                    exit={{ opacity: 0, translateX: -400 }}
                    transition={{
                      type: 'timing',
                      duration: 250,
                      easing: Easing.out(Easing.quad),
                    }}
                  >
                    <ClassCard2Sem
                      gradeLevel={gradeLevel.toString()}
                      name={cls.className}
                      teacher={cls.teacher || ''}
                      s1={{ categories: { names: [], weights: [] }, total: cls.sm1 }}
                      s2={{ categories: { names: [], weights: [] }, total: cls.sm2 }}
                      term={"SM1 Grade"}
                    />
                  </MotiView>
                ))}
              </AnimatePresence>
            </View>
          )}
        </View>
      </ScrollView>
      <BottomSheet
        ref={addClassRef}
        index={-1}
        snapPoints={snapPoints}
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
            addClassRef.current?.close();
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
          const snapValue = semesters.length === 2 ? '62%' : '52%';
          addClassRef.current?.snapToPosition(snapValue, { duration: 350 });
          setCurrentSnapPosition(snapValue);
        }}>
          <BottomSheetView className="bg-cardColor p-4">
            <Text className="text-2xl text-main">Add a Class</Text>
            <View className='my-4 border-slate-600 border-[0.5px]'></View>

            <View className="mb-5">
              <Text className="text-sm font-semibold text-main mb-1">Class Name</Text>
              <TextInput
                className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                placeholder="Search for a class name or code"
                value={classQuery}
                autoCapitalize='none'
                autoComplete={undefined}
                onChangeText={(text) => {
                  setClassQuery(text);
                  setName(text);
                  if (debounceRef.current) clearTimeout(debounceRef.current);
                  debounceRef.current = setTimeout(() => {
                    const lower = text.toLowerCase();
                    if (lower.length === 0) {
                      setFilteredClasses([]);
                    } else {
                      setFilteredClasses(
                        availableClasses
                          .filter((cls) => cls.toLowerCase().includes(lower))
                          .slice(0, 5)
                      );
                    }
                  }, 250);
                }}
              />
              {filteredClasses.length > 0 && (
                <View className="mt-2 bg-primary rounded-lg border border-accent overflow-hidden">
                  {filteredClasses.map((item, index) => (
                    <TouchableOpacity
                      key={item}
                      className={`px-4 py-3 ${
                        index !== filteredClasses.length - 1 ? 'border-b border-accent' : ''
                      }`}
                      onPress={() => {
                        setClassQuery(item);
                        setName(item);
                        setFilteredClasses([]);
                      }}
                    >
                      <Text className="text-main font-medium">{item}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              )}
            </View>

            <View className="mb-5">
              <Text className="text-sm font-semibold text-main mb-1">Select Semester(s)</Text>
              <View className="flex-row flex-wrap gap-2">
                {['Fall Semester', 'Spring Semester'].map((sem) => {
                  const selected = semesters.includes(sem);
                  return (
                    <TouchableOpacity
                      key={sem}
                      className={`px-4 py-2 rounded-full border ${
                        selected ? 'bg-highlight border-highlight' : 'bg-primary border-accent'
                      }`}
                      onPress={() => {
                        let next;
                        if (selected) {
                          // Prevent removing the last semester
                          if (semesters.length > 1) {
                            next = semesters.filter((s) => s !== sem);
                          } else {
                            return;
                          }
                        } else {
                          next = [...semesters, sem];
                        }
                        setSemesters(next);

                        // Update snap position if not in keyboard interaction mode
                        const snapValue = next.length === 2 ? '62%' : '52%';
                        if (currentSnapPosition !== '100%') {
                          addClassRef.current?.snapToPosition(snapValue, { duration: 200 });
                          setCurrentSnapPosition(snapValue);
                        }
                      }}
                    >
                      <Text className={`font-medium ${selected ? 'text-highlightText' : 'text-main'}`}>
                        {sem}
                      </Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
            </View>

            {semesters.includes('Fall Semester') && (
              <View className="mb-5">
                <Text className="text-sm font-semibold text-main mb-1">SM1 Grade</Text>
                <TextInput
                  ref={gradeInputRef}
                  className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                  keyboardType="numeric"
                  value={sm1Value}
                  onChangeText={setSm1Value}
                  onBlur={() => {
                    const num = Number(sm1Value);
                    if (!isNaN(num)) setSm1Value(num.toFixed(2));
                    setGrade(num.toFixed(2));
                  }}
                  onSubmitEditing={() => {
                    const num = Number(sm1Value);
                    if (!isNaN(num)) setGrade(num.toFixed(2));
                  }}
                  returnKeyType="done"
                />
              </View>
            )}

            {semesters.includes('Spring Semester') && (
              <View className="mb-5">
                <Text className="text-sm font-semibold text-main mb-1">SM2 Grade</Text>
                <TextInput
                  ref={outOfInputRef}
                  className="border border-accent rounded-md px-4 py-2 text-main bg-primary"
                  keyboardType="numeric"
                  value={outOfValue}
                  onChangeText={setOutOfValue}
                  onBlur={() => {
                    const num = Number(outOfValue);
                    if (!isNaN(num)) setOutOfValue(num.toFixed(2));
                    setOutOf(Number(outOfValue));
                  }}
                  onSubmitEditing={() => {
                    const num = Number(outOfValue);
                    if (!isNaN(num)) setOutOf(Number(num.toFixed(2)));
                  }}
                  returnKeyType="done"
                />
              </View>
            )}

            <TouchableOpacity
              onPress={onSubmit}
              className="bg-highlight rounded-md py-3 mt-2"
            >
              <Text className="text-center text-highlightText font-bold text-lg">Add Class</Text>
            </TouchableOpacity>
          </BottomSheetView>
        </TouchableWithoutFeedback>
      </BottomSheet>
    </>
  );
};

export default EnterGrades;