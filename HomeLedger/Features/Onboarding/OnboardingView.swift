import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Preferences.onboardingCompleteKey) private var onboardingComplete = false
    @Query private var homes: [Home]

    @State private var step = 0
    @State private var homeName = ""
    @State private var homeType: HomeType = .house
    @State private var selectedRooms: Set<String> = RoomSuggestions.defaults

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if step > 0 {
                        Button { go(step - 1) } label: { Image(systemName: "chevron.left").font(.headline).foregroundStyle(.white) }
                            .accessibilityLabel("Back")
                    }
                    Spacer()
                    if step == 0 {
                        Button("Explore with sample data") { startWithSample() }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                            .accessibilityIdentifier("onboarding.sample")
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 20)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: createHome
                    case 2: rooms
                    default: privacyAndReminders
                    }
                }
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
    }

    private func go(_ s: Int) {
        withAnimation(MotionSafe.animation(reduceMotion)) { step = s }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image("LaunchMark").resizable().scaledToFit().frame(width: 104, height: 104)
                    .accessibilityHidden(true)
                Text("HomeLedger").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                Text("Your entire home, organized.").font(.title3).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.bottom, 32)
            sheet {
                VStack(alignment: .leading, spacing: 16) {
                    feature("shippingbox", "Know what you own", "Photos, serial numbers, receipts and values in one place.")
                    feature("checkmark.shield", "Never miss a warranty", "Reminders before coverage ends.")
                    feature("wrench.and.screwdriver", "Stay ahead of upkeep", "Recurring maintenance with a full history.")
                    feature("doc.richtext", "Insurance-ready reports", "A clean PDF inventory whenever you need it.")
                    primaryButton("Get started", id: "onboarding.start") { go(1) }
                }
            }
        }
    }

    private var createHome: some View {
        VStack(spacing: 0) {
            header("Create your home", "Give it a name you'll recognize. You can change it later.")
            sheet {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("e.g. Maple Street House", text: $homeName)
                        .font(.title3)
                        .padding(14)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .submitLabel(.next)
                        .accessibilityIdentifier("onboarding.homeName")
                    Text("Home type (optional)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(HomeType.allCases) { t in
                            FilterChip(title: t.label, symbol: t.symbol, isSelected: homeType == t) { homeType = t }
                        }
                    }
                    primaryButton("Continue", id: "onboarding.continue") { go(2) }
                        .disabled(homeName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(homeName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
            }
        }
    }

    private var rooms: some View {
        VStack(spacing: 0) {
            header("Add some rooms", "Optional — pick a few to start. Rooms help you find things and build reports.")
            sheet {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(RoomSuggestions.all, id: \.name) { s in
                            FilterChip(title: s.name, symbol: s.symbol, isSelected: selectedRooms.contains(s.name)) {
                                if selectedRooms.contains(s.name) { selectedRooms.remove(s.name) } else { selectedRooms.insert(s.name) }
                            }
                        }
                    }
                    primaryButton(selectedRooms.isEmpty ? "Skip rooms" : "Continue with \(selectedRooms.count) room\(selectedRooms.count == 1 ? "" : "s")", id: "onboarding.rooms") { go(3) }
                }
            }
        }
    }

    private var privacyAndReminders: some View {
        VStack(spacing: 0) {
            header("Private by design", "No account needed. Here's how HomeLedger works.")
            sheet {
                VStack(alignment: .leading, spacing: 16) {
                    feature("iphone", "Stored on this iPhone", "Your records, photos and documents stay on your device. Nothing is uploaded.")
                    feature("text.viewfinder", "On-device text recognition", "Receipts are read by your iPhone, not a cloud service.")
                    feature("icloud.slash", "iCloud sync isn't available yet", "Use Back up & restore in Settings to keep a copy or move to a new phone.")
                    feature("bell.badge", "Helpful reminders", "Get a heads-up before warranties end and when maintenance is due. You choose what to be reminded about.")
                    primaryButton("Allow reminders & finish", id: "onboarding.allowReminders") { finish(requestNotifications: true) }
                    Button("Not now") { finish(requestNotifications: false) }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("onboarding.finish")
                }
            }
        }
    }

    // MARK: Building blocks

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.body).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    private func sheet<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content().padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
        .ignoresSafeArea(edges: .bottom)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: symbol, tint: Theme.brand, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(detail).font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func primaryButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.brand)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
        .accessibilityIdentifier(id)
    }

    // MARK: Actions

    private func finish(requestNotifications: Bool) {
        let roomSpecs = RoomSuggestions.all.filter { selectedRooms.contains($0.name) }.map { ($0.name, $0.symbol) }
        let home = DataService(context: context).createHome(name: homeName.isEmpty ? "My Home" : homeName, type: homeType, roomNames: roomSpecs)
        try? context.save()
        app.selectedHomeID = home.id
        // "Not now" only defers the system prompt — reminders stay on and permission is requested
        // later, in context, when the user first saves a task or warranty.
        if requestNotifications && !app.launch.isUITesting {
            Task { _ = await NotificationService.shared.requestPermission() }
        }
        onboardingComplete = true
    }

    private func startWithSample() {
        if homes.isEmpty {
            let home = SampleDataService(context: context).seed()
            app.selectedHomeID = home.id
        }
        onboardingComplete = true
        app.showToast("Sample home loaded — remove it anytime in Settings")
    }
}
