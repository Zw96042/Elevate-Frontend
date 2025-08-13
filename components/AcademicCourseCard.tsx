import React from 'react';
import { View, Text } from 'react-native';

interface CourseData {
  terms: string;
  finalGrade: string;
  sm1: string;
  sm2: string;
  pr1: string;
  pr2: string;
  pr3: string;
  pr4: string;
  pr5: string;
  pr6: string;
  pr7: string;
  pr8: string;
  rc1: string;
  rc2: string;
  rc3: string;
  rc4: string;
  ex1: string;
  ex2: string;
}

interface AcademicCourseCardProps {
  courseName: string;
  courseData: CourseData;
}

const AcademicCourseCard: React.FC<AcademicCourseCardProps> = ({ courseName, courseData }) => {
  // Helper function to get course level
  const getCourseLevel = (className: string): "AP" | "Honors" | "Regular" => {
    const normalized = className.toLowerCase();
    
    const apExceptions = ["multivariable calculus", "linear algebra", "stats 2: beyond ap statistics", "computer science 2", "computer science 3", "organic chemistry", "art historical methods"];
    const honorsExceptions = ["editorial leadership", "anatomy & physiology", "mentorship", "health science clinical", "robotics", "swift coding", "business incubator", "engineering"];
    
    const isAP = /\bap\b/.test(normalized) || apExceptions.some(ex => normalized.includes(ex));
    if (isAP) return "AP";
    
    const isHonors = /\bhonors?\b/.test(normalized) || honorsExceptions.some(ex => normalized.includes(ex));
    if (isHonors) return "Honors";
    
    return "Regular";
  };

  const courseLevel = getCourseLevel(courseName);
  
  // Get badge color based on course level
  const getBadgeColor = () => {
    switch (courseLevel) {
      case "AP": return "bg-purple-600";
      case "Honors": return "bg-blue-600";
      default: return "bg-gray-600";
    }
  };

  // Format grade display
  const formatGrade = (grade: string) => {
    if (!grade || grade === "" || grade === "P" || grade === "X") {
      return "—";
    }
    const num = Number(grade);
    return isNaN(num) ? grade : num.toFixed(1);
  };

  // Get letter grade
  const getLetterGrade = (grade: string) => {
    const num = Number(grade);
    if (isNaN(num) || !grade || grade === "" || grade === "P" || grade === "X") return "";
    
    if (num >= 97) return "A+";
    if (num >= 93) return "A";
    if (num >= 90) return "A-";
    if (num >= 87) return "B+";
    if (num >= 83) return "B";
    if (num >= 80) return "B-";
    if (num >= 77) return "C+";
    if (num >= 73) return "C";
    if (num >= 70) return "C-";
    if (num >= 67) return "D+";
    if (num >= 65) return "D";
    return "F";
  };

  return (
    <View className="mx-6 mb-4">
      <View className="bg-cardColor rounded-2xl p-4 border border-accent shadow-sm">
        {/* Header */}
        <View className="flex-row items-start justify-between mb-3">
          <View className="flex-1 mr-3">
            <Text className="text-main font-semibold text-base leading-tight" numberOfLines={2}>
              {courseName}
            </Text>
            <Text className="text-accent text-sm mt-1">
              Terms: {courseData.terms}
            </Text>
          </View>
          <View className={`px-2 py-1 rounded-full ${getBadgeColor()}`}>
            <Text className="text-white text-xs font-medium">
              {courseLevel}
            </Text>
          </View>
        </View>

        {/* Semester Grades */}
        <View className="flex-row space-x-4">
          {/* Fall Semester (SM1) */}
          <View className="flex-1">
            <View className="bg-primary rounded-lg p-3 border border-accent">
              <Text className="text-accent text-xs font-medium mb-1">Fall Semester</Text>
              <View className="flex-row items-end justify-between">
                <Text className="text-main text-2xl font-bold">
                  {formatGrade(courseData.sm1)}
                </Text>
                {courseData.sm1 && courseData.sm1 !== "" && courseData.sm1 !== "P" && courseData.sm1 !== "X" && (
                  <Text className="text-accent text-sm font-medium">
                    {getLetterGrade(courseData.sm1)}
                  </Text>
                )}
              </View>
            </View>
          </View>

          {/* Spring Semester (SM2) */}
          <View className="flex-1">
            <View className="bg-primary rounded-lg p-3 border border-accent">
              <Text className="text-accent text-xs font-medium mb-1">Spring Semester</Text>
              <View className="flex-row items-end justify-between">
                <Text className="text-main text-2xl font-bold">
                  {formatGrade(courseData.sm2)}
                </Text>
                {courseData.sm2 && courseData.sm2 !== "" && courseData.sm2 !== "P" && courseData.sm2 !== "X" && (
                  <Text className="text-accent text-sm font-medium">
                    {getLetterGrade(courseData.sm2)}
                  </Text>
                )}
              </View>
            </View>
          </View>
        </View>

        {/* Final Grade */}
        {courseData.finalGrade && courseData.finalGrade !== "" && courseData.finalGrade !== "P" && (
          <View className="mt-3 pt-3 border-t border-accent">
            <View className="flex-row items-center justify-between">
              <Text className="text-accent text-sm font-medium">Final Grade</Text>
              <View className="flex-row items-center space-x-2">
                <Text className="text-main text-lg font-semibold">
                  {formatGrade(courseData.finalGrade)}
                </Text>
                <Text className="text-accent text-sm">
                  {getLetterGrade(courseData.finalGrade)}
                </Text>
              </View>
            </View>
          </View>
        )}
      </View>
    </View>
  );
};

export default AcademicCourseCard;
