import SwiftUI

/// "Get Wallpapers": describe what you want, pick static/animated and an agent, copy the prompt, collect results.
struct StudioView: View {
    @Environment(AgentStudio.self) private var studio
    @Environment(LibraryStore.self) private var library
    let showLibrary: () -> Void

    private let suggestions = ["Mountains", "Neon city at night", "Deep space", "Minimal dark", "Ocean", "Rainy forest", "Abstract gradients", "Cozy interiors"]

    var body: some View {
        @Bindable var studio = studio
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Get Wallpapers").font(.aura(size: 30, .bold))
                    Text("Let your AI agent find new wallpapers. Aura writes the prompt, and the results land in your library.")
                        .foregroundStyle(.secondary)
                }

                step(1, "What do you want?") {
                    TextField("Anything: a place, a mood, a style, a game, a character…", text: $studio.subject)
                        .textFieldStyle(.plain)
                        .font(.aura(size: 22, .semibold))
                        .padding(12)
                        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestions, id: \.self) { name in
                                Button(name) { studio.subject = name }
                                    .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
                            }
                        }
                    }
                    TextField("Extra wishes (optional): warm colors, no people, ultrawide, photography only…", text: $studio.hints)
                        .font(.aura(.body))
                        .textFieldStyle(.roundedBorder)
                }

                step(2, "Static or animated?") {
                    HStack(spacing: 12) {
                        ForEach(WallpaperKind.allCases) { kind in
                            choice(kind.title, kind.symbol, kind == .live ? "Looping video, paused when covered" : "Still image, up to 8K",
                                   selected: studio.kind == kind) { studio.kind = kind }
                        }
                    }
                    Stepper("How many: \(studio.count)", value: $studio.count, in: 2...20)
                        .fixedSize()
                }

                step(3, "Which agent?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(AgentTarget.allCases) { agent in
                            choice(agent.rawValue, agent.symbol, agent.hasShell ? "Downloads for you" : "Replies with links",
                                   selected: studio.agent == agent) { studio.agent = agent }
                        }
                    }
                    Label(studio.agent.howTo, systemImage: "info.circle").font(.aura(.callout)).foregroundStyle(.secondary)
                }

                step(4, "Copy the prompt") {
                    Text(studio.prompt)
                        .font(.auraMono(.callout))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .frame(maxHeight: 220, alignment: .top)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .clipped()
                    HStack {
                        if studio.agent.supportsACP {
                            Button { studio.runNow() } label: {
                                Label(studio.acp.isActive ? "Running…" : "Run Now", systemImage: "play.fill")
                                    .frame(minWidth: 130)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(studio.acp.isActive)
                        }
                        Button { studio.copyPrompt() } label: {
                            Label(copiedRecently ? "Copied" : "Copy Prompt", systemImage: copiedRecently ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                                .frame(minWidth: 130)
                        }
                        .buttonStyle(studio.agent.supportsACP ? GlassButtonStyle() : GlassButtonStyle(prominent: true))
                        if studio.agent.destination != nil {
                            Button { studio.copyPrompt(open: true) } label: {
                                Label("Copy & Open \(studio.agent.hasShell && studio.agent != .cursor ? "Terminal" : studio.agent.rawValue)", systemImage: "arrow.up.forward.app")
                            }
                            .controlSize(.large)
                        }
                        Spacer()
                        if !studio.canCopy { Text("Describe what you want first").font(.aura(.callout)).foregroundStyle(.orange) }
                    }
                    .disabled(!studio.canCopy)
                }

                if studio.acp.phase != .idle {
                    AgentRunPanel(session: studio.acp)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                step(5, "Bring the results in") { results }
            }
            .padding(28)
            .animation(.auraSpring, value: studio.acp.phase)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Get Wallpapers")
    }

    private var copiedRecently: Bool { studio.lastCopied.map { Date.now.timeIntervalSince($0) < 3 } ?? false }

    @ViewBuilder private var results: some View {
        HStack(spacing: 12) {
            Image(systemName: library.newArrivals.isEmpty ? "tray" : "sparkles")
                .font(.aura(.title2)).foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: studio.lastCopied != nil && library.newArrivals.isEmpty)
            VStack(alignment: .leading, spacing: 2) {
                Text(library.newArrivals.isEmpty ? "Watching your library…" : "\(library.newArrivals.count) new wallpapers arrived")
                    .font(.aura(.headline))
                Text("Coding agents save into ~/Pictures/Wallpapers. They show up here by themselves.")
                    .font(.aura(.callout)).foregroundStyle(.secondary)
            }
            Spacer()
            if !library.newArrivals.isEmpty { Button("Show Them", action: showLibrary).buttonStyle(.glassProminent) }
        }

        if !library.newArrivals.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(library.items.filter { library.newArrivals.contains($0.id) }) { w in
                        Thumbnail(wallpaper: w, size: 260)
                            .frame(width: 160, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }

        Divider()

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat agent?").font(.aura(.headline))
                Text("Copy its whole reply, then paste it here. Aura downloads every link.").font(.aura(.callout)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { studio.pasteReply() } label: { Label("Paste Reply", systemImage: "doc.on.clipboard") }
                .controlSize(.large)
        }

        if !studio.jobs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(studio.jobs) { job in
                    HStack(spacing: 8) {
                        switch job.state {
                        case .running: ProgressView().controlSize(.small)
                        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(job.source.host() ?? job.source.absoluteString).font(.aura(.callout, .medium))
                            switch job.state {
                            case .running: Text(job.source.lastPathComponent).font(.aura(.caption)).foregroundStyle(.secondary)
                            case .done(let name): Text(name).font(.aura(.caption)).foregroundStyle(.secondary)
                            case .failed(let why): Text(why).font(.aura(.caption)).foregroundStyle(.red)
                            }
                        }
                        .lineLimit(1)
                    }
                }
            }
        }
    }

    private func step<Content: View>(_ n: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("\(n)")
                        .font(.aura(.callout, .bold))
                        .frame(width: 24, height: 24)
                        .background(.tint, in: Circle())
                        .foregroundStyle(.white)
                    Text(title).font(.aura(.title3, .bold))
                }
                content()
            }
        }
    }

    private func choice(_ title: String, _ symbol: String, _ caption: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.auraSpring) { action() } } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.aura(.title2)).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.aura(.headline))
                    Text(caption).font(.aura(.caption)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.background.opacity(0.35)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.08)), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Live view of an agent run over ACP: status, tool calls, permission prompts and the agent's reply.
struct AgentRunPanel: View {
    let session: ACPSession

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    statusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.agent?.rawValue ?? "Agent").font(.aura(.title3, .bold))
                        Text(statusText).font(.aura(.callout)).foregroundStyle(.secondary)
                    if session.allowAll && session.isActive {
                        Label("Allowing everything this run", systemImage: "checkmark.shield.fill")
                            .font(.aura(.caption, .medium)).foregroundStyle(.orange)
                    }
                    }
                    Spacer()
                    if session.isActive {
                        Button("Stop", role: .destructive) { session.stop() }.buttonStyle(.glass)
                    }
                }

                ForEach(session.permissions) { request in
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Allow this?", systemImage: "hand.raised.fill").font(.aura(.headline)).foregroundStyle(.orange)
                        Text(request.title).font(.auraMono(.callout)).textSelection(.enabled).lineLimit(6)
                        HStack {
                            ForEach(request.options) { option in
                                Button(option.name) { withAnimation(.auraSpring) { session.respond(request, optionID: option.id) } }
                                    .buttonStyle(GlassButtonStyle(prominent: option.kind.hasPrefix("allow")))
                            }
                            Spacer()
                            Button { withAnimation(.auraSpring) { session.approveAll(request) } } label: {
                                Label("Allow All", systemImage: "checkmark.seal")
                            }
                            .buttonStyle(.glass)
                            .help("Approve this and everything else the agent asks for until this run ends")
                        }
                    }
                    .padding(14)
                    .glass(cornerRadius: 14, tint: .orange, shadow: false)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }

                if !session.tools.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(session.tools.suffix(8)) { tool in
                            HStack(spacing: 8) {
                                toolIcon(tool.status)
                                Text(tool.title).font(.aura(.callout)).lineLimit(1).truncationMode(.middle)
                            }
                            .transition(.opacity.combined(with: .offset(y: 6)))
                        }
                    }
                }

                if !session.transcript.isEmpty {
                    ScrollView {
                        Text(session.transcript)
                            .font(.aura(.callout))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(maxHeight: 200)
                    .padding(12)
                    .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .animation(.auraSpring, value: session.permissions.count)
            .animation(.auraSpring, value: session.tools.count)
        }
    }

    private var statusText: String {
        switch session.phase {
        case .idle: ""
        case .starting: "Starting… (the first run downloads the agent adapter)"
        case .running: session.permissions.isEmpty ? "Working. New wallpapers show up in your library as they arrive." : "Waiting for your approval"
        case .finished(let why): why
        case .failed(let why): why
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch session.phase {
        case .starting, .running: ProgressView().controlSize(.small).frame(width: 28)
        case .finished: Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green).frame(width: 28)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange).frame(width: 28)
        case .idle: EmptyView()
        }
    }

    @ViewBuilder private func toolIcon(_ status: String) -> some View {
        switch status {
        case "completed": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case "failed": Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case "in_progress": ProgressView().controlSize(.mini)
        default: Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        }
    }
}
