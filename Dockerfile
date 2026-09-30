# Sowline India — container image. Runs on Cloud Run and on a plain Docker
# host behind nginx; both inject PORT and expect the process on 0.0.0.0.
#
# Multi-stage: the build stage carries dev dependencies and the Next.js
# toolchain; the runtime stage carries only the standalone server output, so
# the shipped image does not contain the seed generator's dev tooling.

FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:22-slim AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# NEXT_PUBLIC_* is inlined into the client bundle at BUILD time, not read at
# runtime. `.dockerignore` excludes .env, so without these args the browser
# bundle silently falls back to the defaults in lib/api-auth.ts and
# lib/firebase/client.ts — Firebase off, and x-api-key stuck at "abc" while
# the server checks a different X_API_KEY. Pass them via build args.
ARG NEXT_PUBLIC_X_API_KEY
ARG NEXT_PUBLIC_FIREBASE_API_KEY
ARG NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN
ARG NEXT_PUBLIC_FIREBASE_PROJECT_ID
ARG NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET
ARG NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID
ARG NEXT_PUBLIC_FIREBASE_APP_ID
ARG NEXT_PUBLIC_GEMINI_LIVE_MODEL
ARG NEXT_PUBLIC_GEMINI_VOICE

# next.config.ts sets output:"standalone", which traces exactly the runtime
# files this app needs.
RUN npm run build

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
# Cloud Run injects PORT; 8080 is its default.
ENV PORT=8080
ENV HOSTNAME=0.0.0.0

RUN groupadd --system --gid 1001 nodejs \
 && useradd --system --uid 1001 --gid nodejs nextjs

COPY --from=build --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=build --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=build --chown=nextjs:nodejs /app/public ./public

USER nextjs
EXPOSE 8080
CMD ["node", "server.js"]
