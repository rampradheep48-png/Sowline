import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Cloud Run wants a self-contained server directory, not a node_modules tree.
  output: "standalone",

  // The seed bundle and the engine run inside server components; firebase-admin
  // and the Google SDK must not be bundled into that trace by value.
  serverExternalPackages: ["firebase-admin"],
};

export default nextConfig;
