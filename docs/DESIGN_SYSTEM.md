# HomeLedger Design System

Direction: calm, premium Apple-quality utility, informed by the reference imagery supplied (royal-blue hero header with circular quick actions and a rounded white content sheet; soft pastel dashboard with gradient highlight tiles; floating pill navigation). All artwork is original (SF Symbols + generated vector-style icon).

## Color tokens (`DesignSystem/Theme.swift`)

| Token | Light | Dark | Use |
|---|---|---|---|
| `brand` | #1E3FA0 | #6F8CFF | Primary actions, selected states |
| `heroTop → heroBottom` | #2347B5 → #1A3893 | #1B2A6B → #141F52 | Dashboard hero, onboarding, launch |
| `canvas` | #F3F4F8 | #0C0E14 | Screen background |
| `card` | #FFFFFF | #171A23 | Cards and rows |
| `ink / inkSecondary / inkTertiary` | #11142B / #5D6275 / #8A8FA3 | #F2F3F8 / #A3A8BA / #7A7F92 | Text hierarchy |
| `success / warning / danger / info` | #18804F / #B86A00 / #C23434 / #4B4BC8 | lighter variants | **Status only** |
| Tints (blue, green, orange, purple, teal, pink) | — | — | Icon badges, at 12% opacity backgrounds |

Gradients appear only on the hero and two highlight tiles per screen (indigo, warm).

## Typography
System San Francisco with Dynamic Type text styles throughout. Large numbers use the rounded design (`.largeTitle` / `.title2` rounded semibold). No fixed font sizes except the tab bar caption (capped at `xLarge` like the system tab bar).

## Shape & spacing
Radii 24 (hero cards) / 18 (cards) / 12 (chips, small tiles). 16 pt gutter, 12 pt rhythm. Cards: hairline border + soft shadow in light mode, border only in dark mode.

## Components
`IconBadge`, `MetricTile`, `GradientStatCard`, `RingProgress`, `StatusPill`, `SectionHeader`, `EmptyStateView`, `RecordRow`, `AssetRow`, `ListCard`, `FilterChip`, `DetailRow`, `MoneyField`, `OptionalDatePicker`, `HeroActionButton`, `FloatingTabBar`.

## Navigation
Floating pill tab bar: Home · My Home · **+** · Maintenance · Documents. The center **+** opens an Add sheet (item, scan, import, task, repair, expense). Settings, search/assistant and premium are reachable from the dashboard toolbar without cluttering the tab bar.

## Accessibility
- Every icon-only control has an accessibility label; decorative icons are hidden.
- Rows combine children into single VoiceOver elements with meaningful labels.
- Reduce Motion disables springs/transitions (`MotionSafe`, `PressableStyle`).
- Color is never the only signal — status pills always include text.
- Touch targets ≥ 44 pt; layouts tested at accessibility text sizes via screenshot automation.
