import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { SESSION_COOKIE, canAccess, decodeSession, homeFor } from "@/lib/auth";

/**
 * The gate, enforced before any page renders.
 *
 * Doing it here rather than in each page means a role cannot reach a surface by
 * typing its URL — the nav hiding a link is cosmetic, this is the actual rule.
 * API routes keep their own `x-api-key` check and are left alone.
 */
export function proxy(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const session = decodeSession(request.cookies.get(SESSION_COOKIE)?.value);

  if (pathname === "/login") {
    if (session) return NextResponse.redirect(new URL(homeFor(session.role), request.url));
    return NextResponse.next();
  }

  if (!session) {
    const url = new URL("/login", request.url);
    url.searchParams.set("next", pathname + search);
    return NextResponse.redirect(url);
  }

  if (!canAccess(session.role, pathname)) {
    return NextResponse.redirect(new URL(homeFor(session.role), request.url));
  }

  return NextResponse.next();
}

export const config = {
  // Everything a person can navigate to. API routes, build output and static
  // assets are excluded: gating those would break the login page itself.
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico|.*\\.(?:png|jpg|jpeg|svg|webp|ico)$).*)"],
};
