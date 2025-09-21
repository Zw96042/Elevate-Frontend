import React, { createContext, useContext, useRef, useState, ReactNode } from 'react';
import { Keyboard } from 'react-native';
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
  filteredAssignments: Assignment[];
  className: string;
  classId?: string;
  corNumId?: string;
  section?: string;
  gbId?: string;
  selectedCategory: string;
  currTerm: TermData;
  artificialAssignments: Assignment[];
  setArtificialAssignments: React.Dispatch<React.SetStateAction<Assignment[]>>;
  setFilteredAssignments: React.Dispatch<React.SetStateAction<Assignment[]>>;
  categories: string[];
  setCourseSummary: React.Dispatch<React.SetStateAction<any>>;
  calculateGradeSummary: (assignments: Assignment[], weights: Record<string, number>) => any;
  isEnabled: boolean;
  meshAssignments?: () => void;
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

  setCategories(data.categories);
  setCategory('');
  setName('');
  setGrade('100');
  setOutOf(100);
  setTerm(data.selectedCategory);
  setClassName(formatClassName(data.className));

  // console.log("Opening modal for class:", data.className, "with ID:", data.classId);
  addSheetRef.current?.expand();
  // console.log("res: ", addSheetRef.current);
  };

  const onSubmit = async () => {
    if (!modalData) return;

    const assignment = {
      id: generateUniqueId(), // Generate unique ID for new assignments
      className: modalData.className,
      name,
      term: modalData.selectedCategory.split(" ")[0], // Store the split term format
      category,
      grade,
      outOf,
      dueDate: new Date().toISOString().slice(0, 10).replace(/-/g, "/").slice(5),
      artificial: true,
    };

    const updatedArtificial = [assignment, ...modalData.artificialAssignments];
    modalData.setArtificialAssignments(updatedArtificial);

    // Use real assignments from modalData.filteredAssignments if needed
    const real: Assignment[] = (modalData.filteredAssignments || []).filter(
      (item: Assignment) =>
        item.className === modalData.className &&
        item.term === modalData.selectedCategory.split(" ")[0] &&
        !item.artificial
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
  // Use a stable key for artificial assignments that includes the term
  // Fallback to empty string if any identifier is missing
  const storageKey = `${modalData.className || ''}_${modalData.corNumId || ''}_${modalData.section || ''}_${modalData.gbId || ''}_${modalData.selectedCategory.split(" ")[0]}`;
    if (updatedArtificial.length === 0) {
      // Remove the key if no assignments left
      delete existing[storageKey];
      await AsyncStorage.setItem("artificialAssignments", JSON.stringify(existing));
    } else {
      const updated = {
        ...existing,
        [storageKey]: ensureUniqueAssignmentIds(updatedArtificial),
      };
      await AsyncStorage.setItem("artificialAssignments", JSON.stringify(updated));
    }
    
    // Clear form data
    setName('');
    setGrade('');
    setOutOf(100);
    setCategory(categories[0] || 'Daily');
    
    // Dismiss keyboard before closing modal
    Keyboard.dismiss();
    
    // Small delay to ensure keyboard is fully dismissed
    setTimeout(() => {
      Keyboard.dismiss();
    }, 100);
    
    // Close the modal after a brief delay
    setTimeout(() => {
      addSheetRef.current?.close();
      console.log('🔒 Modal closed from context');
    }, 150);
    
    // Run meshAssignments after adding artificial assignment
    if (modalData?.meshAssignments) {
      modalData.meshAssignments();
    }
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