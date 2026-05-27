import Foundation

struct OnlinePortResearch {
  let summary: String?
  let sources: [PortInspectionSource]
}

enum OnlinePortResearchService {
  static func research(title: String, warnings: [PortInspectionWarning]) async -> OnlinePortResearch {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTitle.isEmpty else {
      return OnlinePortResearch(summary: nil, sources: [])
    }

    var sources = knownSources(for: normalizedTitle)
    if let searchSource = await searchWeb(for: normalizedTitle, warnings: warnings) {
      sources.append(searchSource)
    }

    sources = uniqueSources(sources)
    let summary = sources.isEmpty
      ? nil
      : "Online lookup added \(sources.count) source \(sources.count == 1 ? "reference" : "references") for \(normalizedTitle)."

    return OnlinePortResearch(summary: summary, sources: sources)
  }

  private static func knownSources(for title: String) -> [PortInspectionSource] {
    let lowercased = title.lowercased()

    if lowercased == "cursor" || lowercased.hasPrefix("cursor helper") {
      return [
        PortInspectionSource(
          title: "Electron Process Model",
          url: "https://www.electronjs.org/docs/latest/tutorial/process-model",
          snippet: "Electron apps use a multi-process architecture with renderer and utility/helper processes."
        ),
        PortInspectionSource(
          title: "VS Code Extension Host",
          url: "https://code.visualstudio.com/api/advanced-topics/extension-host",
          snippet: "VS Code-family editors run extension code in extension hosts, so helper counts can scale with windows, extensions, and workspace activity."
        ),
        PortInspectionSource(
          title: "Cursor Security",
          url: "https://cursor.com/security",
          snippet: "Cursor documents its client and backend behavior, including update and marketplace domains."
        ),
      ]
    }

    if lowercased == "ollama" {
      return [
        PortInspectionSource(
          title: "Ollama API",
          url: "https://github.com/ollama/ollama/blob/main/docs/api.md",
          snippet: "Ollama exposes a local HTTP API; port 11434 is the common local API listener."
        ),
      ]
    }

    if lowercased == "tailscale" || lowercased.contains("ipnextension") {
      return [
        PortInspectionSource(
          title: "Tailscale Serve",
          url: "https://tailscale.com/kb/1242/tailscale-serve",
          snippet: "Tailscale Serve can publish local services through your tailnet."
        ),
        PortInspectionSource(
          title: "Tailscale Funnel",
          url: "https://tailscale.com/kb/1223/funnel",
          snippet: "Tailscale Funnel can expose selected services to the public internet."
        ),
      ]
    }

    if lowercased.contains("cloudflare") || lowercased == "cloudflared" {
      return [
        PortInspectionSource(
          title: "Cloudflare Tunnel",
          url: "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/",
          snippet: "Cloudflare Tunnel connects local services to Cloudflare without opening inbound firewall ports."
        ),
      ]
    }

    if lowercased == "ngrok" {
      return [
        PortInspectionSource(
          title: "ngrok Docs",
          url: "https://ngrok.com/docs/",
          snippet: "ngrok can create public endpoints for local services."
        ),
      ]
    }

    return []
  }

  private static func searchWeb(for title: String, warnings: [PortInspectionWarning]) async -> PortInspectionSource? {
    let warningTerms = warnings.isEmpty ? "" : " warning public listening port"
    let query = "\(title) macOS listening port process\(warningTerms)"
    var components = URLComponents(string: "https://api.duckduckgo.com/")
    components?.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "format", value: "json"),
      URLQueryItem(name: "no_html", value: "1"),
      URLQueryItem(name: "skip_disambig", value: "1"),
    ]
    guard let url = components?.url else { return nil }

    var request = URLRequest(url: url)
    request.timeoutInterval = 6

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        return nil
      }

      let heading = stringValue(object["Heading"])
      let abstract = stringValue(object["AbstractText"])
      let abstractURL = stringValue(object["AbstractURL"])

      guard !heading.isEmpty || !abstract.isEmpty || !abstractURL.isEmpty else {
        return nil
      }

      return PortInspectionSource(
        title: heading.isEmpty ? "Web search result" : heading,
        url: abstractURL.isEmpty ? "https://duckduckgo.com/?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title)" : abstractURL,
        snippet: abstract.isEmpty ? nil : abstract
      )
    } catch {
      return nil
    }
  }

  private static func uniqueSources(_ sources: [PortInspectionSource]) -> [PortInspectionSource] {
    var seen = Set<String>()
    var unique: [PortInspectionSource] = []
    for source in sources {
      guard !seen.contains(source.url) else { continue }
      seen.insert(source.url)
      unique.append(source)
    }
    return Array(unique.prefix(5))
  }

  private static func stringValue(_ value: Any?) -> String {
    (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }
}
