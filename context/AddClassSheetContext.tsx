import React, { createContext, useContext, useRef, useState, ReactNode } from 'react';
import AddClass from '@gorhom/bottom-sheet';
import formatClassName from '@/utils/formatClassName';
import AsyncStorage from '@react-native-async-storage/async-storage';

type TermData = {
  categories: {
    names: string[];
    weights: number[];
  };
  total: number;
};

type Assignment = {
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

type AddClassSheetContextType = {
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
  addClassRef: React.RefObject<React.ElementRef<typeof AddClass> | null>;
  onSubmit: () => void;
};

const AddClassSheetContext = createContext<AddClassSheetContextType | undefined>(undefined);

export const AddClassSheetProvider = ({ children }: { children: ReactNode }) => {
  const addClassRef = useRef<React.ElementRef<typeof AddClass> | null>(null);

  const [modalData, setModalData] = useState<ModalData | null>(null);

  const [name, setName] = useState('');
  const [grade, setGrade] = useState('');
  const [outOf, setOutOf] = useState<number>(0);
  const [categories, setCategories] = useState<string[]>([]);
  const [category, setCategory] = useState('');
  const [term, setTerm] = useState('');
  const [className, setClassName] = useState('');

  const openModal = (data: ModalData) => {
    setModalData(data);

    setCategories(data.currTerm.categories.names);
    setCategory('');
    setName('');
    setGrade('');
    setOutOf(0);
    setTerm(data.selectedCategory);
    setClassName(formatClassName(data.className));

    addClassRef.current?.expand();
  };

  const onSubmit = async () => {
    if (!modalData) return;

    const assignment: Assignment = {
      className: modalData.className,
      name,
      term: modalData.selectedCategory.split(" ")[0],
      category,
      grade,
      outOf,
      dueDate: new Date().toISOString().slice(0, 10).replace(/-/g, "/").slice(5),
      artificial: true,
    };

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

    const artificialNames = new Set(artificial.map(a => a.name));
    const filteredReal = real.filter(r => !artificialNames.has(r.name));

    modalData.setFilteredAssignments([...artificial, ...filteredReal]);

    const existing = JSON.parse(await AsyncStorage.getItem("artificialAssignments") ?? "{}");
    const updated = {
      ...existing,
      [modalData.className]: updatedArtificial,
    };

    await AsyncStorage.setItem("artificialAssignments", JSON.stringify(updated));
    addClassRef.current?.close();
  };

  return (
    <AddClassSheetContext.Provider
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
        addClassRef,
        onSubmit,
      }}
    >
      {children}
    </AddClassSheetContext.Provider>
  );
};

export const useAddClassSheet = () => {
  const context = useContext(AddClassSheetContext);
  if (!context) throw new Error('useAddClassSheet must be used within AddClassSheetProvider');
  return context;
};