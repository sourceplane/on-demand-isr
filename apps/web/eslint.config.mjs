// Upstream ships no ESLint config; the port lints with the workspace's shared
// config, as the commerce baselines do. The template's GitHub responses are
// typed `any` (a warning there), and its pages log what they fetch, as
// written.
import config from "../../tooling/eslint/index.js";

export default [...config];
