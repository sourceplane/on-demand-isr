// Next.js's ambient types — the stylesheet modules (`*.module.scss`) and the
// static images (`*.png`) the pages import — for `tsc` on a fresh checkout:
// next-env.d.ts, which carries the same references, is written by `next
// build` and not committed (.gitignore), so the typecheck cannot rely on it.
/// <reference types="next" />
/// <reference types="next/image-types/global" />
