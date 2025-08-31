interface SkywardAuthInfo {
  link: string;
  username: string;
  password: string;
}

interface Message {
  className: string;
  messageRowId: string;
  subject: string;
  from: string;
  date: string;
  content: string;
}

interface Class {
  name: string;
  teacher: string;
  corNumId: string;
  stuId: string;
  section: string;
  gbId: string;
  t1: {
        categories: {
            names: string[];
            weights: number[];
        };
        total: number;
    };
  t2: {
        categories: {
            names: string[];
            weights: number[];
        };
        total: number;
    };
  s1: {
        categories: {
            names: string[];
            weights: number[];
        };
        total: number;
    };
  t3: {
        categories: {
            names: string[];
            weights: number[];
        };
        total: number;
    };
  t4: {
        categories: {
            names: string[];
            weights: number[];
        };
        total: number;
    };
  s2: {
        categories: {
            names: string[];
            weights: number[];
        };
        total: number;
    };
}

interface Assignment {
  id?: string; // Optional for backward compatibility
  className: string;
  name: string;
  term: string;
  category: string;
  grade: string;
  outOf: number;
  dueDate: string;
  artificial: boolean;
}