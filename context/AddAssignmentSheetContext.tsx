import React, { createContext, useContext, useRef, useState, ReactNode } from 'react';
import AddSheet from '@gorhom/bottom-sheet';
import formatClassName from '@/utils/formatClassName';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { generateUniqueId, ensureUniqueAssignmentIds } from '@/utils/uniqueId';

type TermData = {
  categories: {
    names: string[];
    weights: number[];
  };
  total: number | string; // Allow both number and string (for "--")
};

type Assignment = {
  id?: string;
  className: string;
  name: string;
  term: string;
  category: string;
  grade: string;
  outOf: number;
  dueDate: string;
  artificial: boolean;
};

type ModalData = {
  className: string;
  selectedCategory: string;
  currTerm: TermData;
  artificialAssignments: Assignment[];
  setArtificialAssignments: React.Dispatch<React.SetStateAction<Assignment[]>>;
  setFilteredAssignments: React.Dispatch<React.SetStateAction<Assignment[]>>;
  ASSIN: Assignment[];
  setCourseSummary: React.Dispatch<React.SetStateAction<any>>;
  calculateGradeSummary: (assignments: Assignment[], weights: Record<string, number>) => any;
  isEnabled: boolean;
};

type AddAssignmentSheetContextType = {
  openModal: (data: ModalData) => void;
  modalData: ModalData | null;
  setModalData: React.Dispatch<React.SetStateAction<ModalData | null>>;
  name: string;
  setName: React.Dispatch<React.SetStateAction<string>>;
  grade: string;
  setGrade: React.Dispatch<React.SetStateAction<string>>;
  outOf: number;
  setOutOf: React.Dispatch<React.SetStateAction<number>>;
  categories: string[];
  setCategories: React.Dispatch<React.SetStateAction<string[]>>;
  category: string;
  setCategory: React.Dispatch<React.SetStateAction<string>>;
  term: string;
  setTerm: React.Dispatch<React.SetStateAction<string>>;
  className: string;
  setClassName: React.Dispatch<React.SetStateAction<string>>;
  addSheetRef: React.RefObject<React.ElementRef<typeof AddSheet> | null>;
  onSubmit: () => void;
};

const AddSheetContext = createContext<AddAssignmentSheetContextType | undefined>(undefined);

export const AddSheetProvider = ({ children }: { children: ReactNode }) => {
  const addSheetRef = useRef<React.ElementRef<typeof AddSheet> | null>(null);

  const [modalData, setModalData] = useState<ModalData | null>(null);

  const [name, setName] = useState('');
  const [grade, setGrade] = useState('100');
  const [outOf, setOutOf] = useState<number>(100);
  const [categories, setCategories] = useState<string[]>([]);
  const [category, setCategory] = useState('');
  const [term, setTerm] = useState('');
  const [className, setClassName] = useState('');

  const openModal = (data: ModalData) => {
    setModalData(data);

    setCategories(data.currTerm.categories.names);
    setCategory('');
    setTerm(data.selectedCategory);
    setClassName(formatClassName(data.className));

    addSheetRef.current?.expand();
  };

  const onSubmit = async () => {
    if (!modalData) return;

    const assignment = {
      id: generateUniqueId(), // Generate unique ID for new assignments
      className: modalData.className,
      name,
      term: modalData.selectedCategory.split(" ")[0],
      category,
      grade,
      outOf,
      dueDate: new Date().toISOString().slice(0, 10).replace(/-/g, "/").slice(5),
      artificial: true,
    };

    console.log(assignment);
    const updatedArtificial = [assignment, ...modalData.artificialAssignments];
    modalData.setArtificialAssignments(updatedArtificial);

    const real = modalData.ASSIN.filter(
      item =>
        item.className === modalData.className &&
        item.term === modalData.selectedCategory.split(" ")[0]
    );

    const artificial = modalData.isEnabled
      ? updatedArtificial.filter(
          a =>
            a.className === modalData.className &&
            a.term === modalData.selectedCategory.split(" ")[0]
        )
      : [];

    // Use ID-based filtering instead of name-based
    const artificialIds = new Set(artificial.map(a => a.id).filter(Boolean));
    const artificialNames = new Set(artificial.map(a => a.name)); // Keep name fallback for compatibility
    const filteredReal = real.filter(r => 
      !artificialIds.has(r.id) && !artificialNames.has(r.name)
    );

    // Ensure all assignments have unique IDs
    const allAssignments = ensureUniqueAssignmentIds([...artificial, ...filteredReal]);
    modalData.setFilteredAssignments(allAssignments);

    const existing = JSON.parse(await AsyncStorage.getItem("artificialAssignments") ?? "{}");
    const updated = {
      ...existing,
      [modalData.className]: ensureUniqueAssignmentIds(updatedArtificial),
    };

    await AsyncStorage.setItem("artificialAssignments", JSON.stringify(updated));
    addSheetRef.current?.close();
  };

  return (
    <AddSheetContext.Provider
      value={{
        openModal,
        modalData,
        setModalData,
        name,
        setName,
        grade,
        setGrade,
        outOf,
        setOutOf,
        categories,
        setCategories,
        category,
        setCategory,
        term,
        setTerm,
        className,
        setClassName,
        addSheetRef,
        onSubmit,
      }}
    >
      {children}
    </AddSheetContext.Provider>
  );
};

export const useAddAssignmentSheet = () => {
  const context = useContext(AddSheetContext);
  if (!context) throw new Error('useAddSheet must be used within AddSheetProvider');
  return context;
};