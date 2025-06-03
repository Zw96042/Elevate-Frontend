const formatClassName = (raw: string) => {
  if (raw.endsWith("FF")) return "Invention & Innovation FF";
  return raw
    .toLowerCase()
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
};

export default formatClassName