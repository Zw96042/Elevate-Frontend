const formatClassName = (raw: string) => {
  if (raw.endsWith("FF")) return "Invention & Innovation FF";
  if (raw.endsWith("HONORS")) {
    raw = raw.replace("HONORS", "H").trim();
  }

  if (raw.includes("HAYLEY")) return "Kelly Rosier";

  const acronyms = new Set(["AP", "IB", "GT", "ELA", "BC", "AB", "CSA", "CSP", "APUSH", "US", "UK", "EU", "PE", "IT", "CS", "AI", "ML", "CAD", "CTE", "STEM"]);

  return raw
    .toUpperCase()
    .split('_')
    .map(word => {
      if (acronyms.has(word)) return word;
      if (/i{2,}/i.test(word)) return word.toUpperCase();
      return word.charAt(0) + word.slice(1).toLowerCase();
    })
    .join(' ');
};

export default formatClassName