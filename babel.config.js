module.exports = function (api) {
  const isProduction = api.env('production');
  return {
    presets: [
      ["babel-preset-expo", { jsxImportSource: "nativewind" }],
      "nativewind/babel",
    ],
    plugins: isProduction ? [removeConsoleCalls] : [],
  };
};

// Academic data is intentionally never emitted to device logs in release
// builds. Development retains diagnostics through the gated logger.
function removeConsoleCalls({ types: t }) {
  return {
    visitor: {
      CallExpression(path) {
        const callee = path.node.callee;
        if (
          t.isMemberExpression(callee) &&
          t.isIdentifier(callee.object, { name: 'console' })
        ) {
          path.remove();
        }
      },
    },
  };
}
