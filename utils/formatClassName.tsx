const formatClassName = (raw: string) => {
  if (raw.endsWith("FF")) return "Invention & Innovation FF";

  const acronyms = new Set(["AP", "IB", "GT", "ELA"]);

  return raw
    .toUpperCase()
    .split('_')
    .map(word => acronyms.has(word) ? word : word.charAt(0) + word.slice(1).toLowerCase())
    .join(' ');
};

export default formatClassName