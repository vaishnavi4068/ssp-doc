# 44 — `ssp-ui` Repository Structure

Implements `experiences/portal-ui/16-ui-spec.md` (`16-ui-spec.md`) and the Sidekick surface of `10-product/17-conversational-provisioning-spec.md` (superseded by `experiences/portal-ui/README.md` and `experiences/agentic-chat/README.md`).

```
ssp-ui/
├── AGENTS.md  .cursor/rules/  CODEOWNERS  package.json (pnpm)  turbo.json
├── apps/storefront/                     Next.js 15 app
│   ├── app/(shell)/layout.tsx           TopBar, LeftNav, BottomComposer, SidekickPanel
│   ├── app/page.tsx                     Storefront Home
│   ├── app/skus/…  app/checkout/[serviceId]/…  app/orders/…  app/resources/…  app/drafts  app/settings
│   ├── app/api/ssp/[...path]/route.ts   authenticated proxy to ssp-cp (adds JWT; streams SSE)
│   ├── components/storefront/           HeroCard, DestinationTabs, DestinationCard, SkuCard, RecentlyViewed, DraftChips, OrderTimeline, RunPanel, ResourceTable
│   ├── components/checkout/             Stepper, StepCard, FieldRow (number + key in mono), RadioCards, ArrayTable, DerivedField, Receipt (Summary|Code tabs), PlaceOrderBar
│   ├── components/sidekick/             Panel, MessageList, PreflightCard, StatusCard, CitationChip, Composer
│   ├── lib/api/                         openapi-typescript client from ssp-doc/10-product/12-openapi.yaml + TanStack Query hooks
│   ├── lib/sse.ts  lib/auth.ts (Auth.js OIDC)  lib/recently-viewed.ts (localStorage)
│   └── tests/e2e/ (Playwright)  tests/fixtures/catalog/{gcp.spanner-instance,unknown-service}/
├── packages/form-renderer/              @ssp/form-renderer: schema+ui.yaml → steps/fields; Ajv 2020; widgets registry; receipt bindings; Storybook
├── packages/ui/                         @ssp/ui: shadcn components, tokens (globals.css), icons, typography; published to GitHub Packages
├── deploy/chart/                        Deployment (standalone Next server), Service, HPA, NetworkPolicy, ConfigMap (API base URL, OIDC issuer)
└── .github/workflows/{ci,release}.yml   lint, typecheck, unit, Storybook build, Playwright against twin-backed sandbox, Lighthouse CI, visual regression
```

## Binding notes

- SSP-UIR-001 No service-specific code anywhere under `apps/storefront`; the `unknown-service` fixture test fails the build otherwise.
- SSP-UIR-002 Money, guardrails, policy results and code views are rendered from server responses only; the renderer has no pricing logic.
- SSP-UIR-003 `@ssp/form-renderer` is framework-light (React only), has 100 % typed widget contracts, and ships a `rendererVersion`; `ui.yaml` declares the version it targets.
- SSP-UIR-004 Tokens live in `packages/ui/src/tokens.css` exactly as in `16-ui-spec.md` §2; the control room and migration apps import them, never redefine them.
- SSP-UIR-005 The storefront proxy enforces same-origin, forwards `Idempotency-Key`, and strips any `X-Request-Id` from the client (server issues it).
- SSP-UIR-006 Accessibility and visual regression gates per `04-definition-of-done.md`.
