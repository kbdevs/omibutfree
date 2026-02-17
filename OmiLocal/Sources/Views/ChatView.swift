import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(appState.chatMessages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if appState.isChatLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 16)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: appState.chatMessages.count) { _ in
                        if let lastMessage = appState.chatMessages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    TextField("Ask Omi anything...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .focused($isInputFocused)
                        .lineLimit(1...5)
                    
                    Button {
                        Task {
                            let message = messageText
                            messageText = ""
                            await appState.sendChatMessage(message)
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(messageText.isEmpty ? .gray : .purple)
                    }
                    .disabled(messageText.isEmpty || appState.isChatLoading)
                }
                .padding()
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        appState.clearChat()
                    }
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if !message.isUser { Spacer() }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(message.isUser ? Color.purple : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.isUser { Spacer() }
        }
    }
}
