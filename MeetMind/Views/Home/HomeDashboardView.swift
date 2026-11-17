import SwiftUI
import SwiftData

/// Main Meetings home screen matching Figma node 161:777
public struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @State public var viewModel: HomeViewModel
    
    @State private var isShowingSettings: Bool = false
    @State private var isMicrophoneCheckPresented: Bool = false
    @State private var isNewMeetingSheetPresented: Bool = false
    
    public init(viewModel: HomeViewModel = HomeViewModel()) { _viewModel = State(initialValue: viewModel) }
    public init(modelContext: ModelContext? = nil) { _viewModel = State(initialValue: HomeViewModel(modelContext: modelContext)) }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MeetingsSearchBarView(text: $viewModel.searchText)
                
                Button(action: { isMicrophoneCheckPresented = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Record a meeting")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(hex: "#0068D9"))
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                }
                
                HomeUpcomingSectionView(meetings: viewModel.filteredUpcomingMeetings) { meeting in
                    router.navigate(to: .meetingDetail(id: meeting.id), in: .home)
                }
                
                HomeRecentSectionView(meetings: viewModel.filteredRecentMeetings) { meeting in
                    router.navigate(to: .meetingDetail(id: meeting.id), in: .home)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(hex: "#F8FAFC"))
        .navigationTitle("Meetings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { isShowingSettings = true }) {
                    Image("ProfileDemo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(hex: "#E4E8F1"), lineWidth: 1))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Schedule meeting", systemImage: "calendar.badge.plus") { isNewMeetingSheetPresented = true }
                    Button("Import audio", systemImage: "square.and.arrow.down") { isNewMeetingSheetPresented = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#1C1C1E"))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "#F0F3FA"))
                        .clipShape(Circle())
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $isMicrophoneCheckPresented) {
            MicrophoneCheckView {
                let m = Meeting(title: "New Meeting \(Date().formatted(date: .omitted, time: .shortened))", createdAt: Date(), duration: 0, status: .recording)
                viewModel.addMeeting(m)
                router.navigate(to: .liveRecording(id: m.id), in: .home)
            }
        }
        .sheet(isPresented: $isNewMeetingSheetPresented) {
            NewMeetingSheet(modelContext: modelContext) { m in
                viewModel.fetchMeetings()
                if m.status == .recording { router.navigate(to: .liveRecording(id: m.id), in: .home) }
            }
        }
        .onAppear { viewModel.setModelContext(modelContext); viewModel.fetchMeetings() }
    }
}
