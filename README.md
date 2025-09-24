# Agents.swift

Swift client for  [Cloudflare Agents](https://github.com/cloudflare/agents) with [Vercel AI SDK](https://github.com/vercel/ai)-compatible chat messages and streaming over WebSockets.

## Quickstart

### Requirements
- Swift 5.9+
- Platforms: iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+

### Installation

Add via Swift Package Manager:

```swift
// In Package.swift dependencies
.package(url: "https://github.com/victorhenrion/Agents.swift.git", from: "0.1.0")
```

Then add the product to your target dependencies:

```swift
.product(name: "Agents", package: "Agents.swift")
```

### Example

```swift
import Foundation
import Agents

struct AppState: Codable {
    let userId: String
}

@MainActor
func helloWorld() async {
    let baseURL = URL(string: "https://your-domain.example.com")!

    // Optional headers (e.g. Authorization)
    let options = AgentClientOptions<AppState>(
        onClientStateUpdate: { state in
            print("Client state set:", state)
        },
        onServerStateUpdate: { state in
            print("Server state:", state)
        },
        onMcpUpdate: { mcp in
            print("MCP servers:", mcp)
        },
        headers: [
            "Authorization": "Bearer <token>"
        ]
    )

    let client = await AgentClient<AppState>(
        baseURL: baseURL,
        agentNamespace: "MyAgent",  // will be converted to "my-agent" in the URL path
        instanceName: "default",
        options: options
    )

    // Set initial state (optional)
    client.setState(AppState(userId: "123"))

    // Send a user message
    let userMessage = ChatMessage(
        id: UUID().uuidString,
        createdAt: Date(),
        role: .user,
        annotations: [],
        parts: [ .text(.init(text: "Hello, agent!")) ]
    )

    do {
        let response = try await client.sendMessage(message: userMessage)
        print("Response:", response)
    } catch {
        print("Error:", error)
    }
}
```

### SwiftUI

`AgentClient` is `@Observable`, so it integrates with SwiftUI’s Observation system. You can observe `client.messages` for live updates as the stream arrives.

## Project status

This is work in progress, use at your own risk!\
Contributions are most welcome—expect future updates.
