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
  className: string;
  name: string;
  term: string;
  category: string;
  grade: number;
  outOf: number;
  dueDate: string;
  artificial: boolean;
}