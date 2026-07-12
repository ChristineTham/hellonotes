//
//  GitHostAPI.swift
//  HelloNotes
//
//  Created by Chris Tham on 12/7/2026.
//
//  Lists the repositories a connected account can access, over the hosting
//  service's REST API (GitHub, GitLab, Gitea/Forgejo, or a compatible custom
//  host). Requires the com.apple.security.network.client entitlement. The token
//  comes from the login Keychain (see GitKeychain); it is sent in the request
//  header only, never logged or persisted by this layer.
//

import Foundation

/// A repository as surfaced by a hosting service, ready to clone.
struct RemoteRepository: Identifiable, Hashable, Sendable {
    var id: String { cloneURL }
    var name: String
    var fullName: String        // "owner/name"
    var cloneURL: String        // HTTPS clone URL
    var description: String?
    var isPrivate: Bool
    var updatedAt: Date?
}

enum GitHostAPI {
    enum APIError: LocalizedError {
        case unauthorized
        case http(Int)
        case unsupportedHost
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Authentication failed. Check the account's token and its scopes."
            case let .http(code):
                return "The server returned HTTP \(code)."
            case .unsupportedHost:
                return "Couldn't determine an API endpoint for this host."
            case let .transport(message):
                return message
            }
        }
    }

    /// Fetch the repositories `account` can access, newest activity first.
    static func repositories(for account: GitAccount, token: String) async throws -> [RemoteRepository] {
        switch account.service {
        case .github: return try await github(host: account.host, token: token)
        case .gitlab: return try await gitlab(host: account.host, token: token)
        case .gitea, .custom: return try await gitea(host: account.host, token: token)
        }
    }

    // MARK: - GitHub

    private static func github(host: String, token: String) async throws -> [RemoteRepository] {
        // github.com uses api.github.com; GitHub Enterprise uses /api/v3.
        let base = host.lowercased() == "github.com"
            ? "https://api.github.com"
            : "https://\(host)/api/v3"
        guard let url = URL(string: "\(base)/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member") else {
            throw APIError.unsupportedHost
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        struct GHRepo: Decodable {
            let name: String
            let full_name: String
            let clone_url: String
            let description: String?
            let `private`: Bool
            let updated_at: String?
        }
        let repos: [GHRepo] = try await getJSON(request)
        return repos.map {
            RemoteRepository(name: $0.name, fullName: $0.full_name, cloneURL: $0.clone_url,
                             description: $0.description, isPrivate: $0.private,
                             updatedAt: parseDate($0.updated_at))
        }
    }

    // MARK: - GitLab

    private static func gitlab(host: String, token: String) async throws -> [RemoteRepository] {
        let base = "https://\(host.isEmpty ? "gitlab.com" : host)"
        guard let url = URL(string: "\(base)/api/v4/projects?membership=true&simple=true&per_page=100&order_by=last_activity_at") else {
            throw APIError.unsupportedHost
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

        struct GLRepo: Decodable {
            let name: String
            let path_with_namespace: String
            let http_url_to_repo: String
            let description: String?
            let visibility: String?
            let last_activity_at: String?
        }
        let repos: [GLRepo] = try await getJSON(request)
        return repos.map {
            RemoteRepository(name: $0.name, fullName: $0.path_with_namespace, cloneURL: $0.http_url_to_repo,
                             description: $0.description, isPrivate: ($0.visibility ?? "private") != "public",
                             updatedAt: parseDate($0.last_activity_at))
        }
    }

    // MARK: - Gitea / Forgejo (and compatible custom hosts)

    private static func gitea(host: String, token: String) async throws -> [RemoteRepository] {
        guard !host.isEmpty, let url = URL(string: "https://\(host)/api/v1/user/repos?limit=50") else {
            throw APIError.unsupportedHost
        }
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")

        struct GTRepo: Decodable {
            let name: String
            let full_name: String
            let clone_url: String
            let description: String?
            let `private`: Bool
            let updated_at: String?
        }
        let repos: [GTRepo] = try await getJSON(request)
        return repos.map {
            RemoteRepository(name: $0.name, fullName: $0.full_name, cloneURL: $0.clone_url,
                             description: $0.description, isPrivate: $0.private,
                             updatedAt: parseDate($0.updated_at))
        }
    }

    // MARK: - Create repository

    /// Create a new repository on `account`'s hosting service and return it
    /// (with the HTTPS clone URL). The repo is created empty (no auto-init) so
    /// the local first commit can be pushed to it.
    static func createRepository(named name: String, isPrivate: Bool,
                                 for account: GitAccount, token: String) async throws -> RemoteRepository {
        switch account.service {
        case .github:
            let base = account.host.lowercased() == "github.com"
                ? "https://api.github.com" : "https://\(account.host)/api/v3"
            var request = try postRequest("\(base)/user/repos")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": name, "private": isPrivate, "auto_init": false,
            ])
            struct GHRepo: Decodable { let name: String; let full_name: String; let clone_url: String; let `private`: Bool }
            let r: GHRepo = try await sendJSON(request)
            return RemoteRepository(name: r.name, fullName: r.full_name, cloneURL: r.clone_url,
                                    description: nil, isPrivate: r.private, updatedAt: nil)

        case .gitlab:
            guard !account.host.isEmpty else { throw APIError.unsupportedHost }
            var request = try postRequest("https://\(account.host)/api/v4/projects")
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": name, "visibility": isPrivate ? "private" : "public",
            ])
            struct GLRepo: Decodable { let name: String; let path_with_namespace: String; let http_url_to_repo: String; let visibility: String? }
            let r: GLRepo = try await sendJSON(request)
            return RemoteRepository(name: r.name, fullName: r.path_with_namespace, cloneURL: r.http_url_to_repo,
                                    description: nil, isPrivate: r.visibility != "public", updatedAt: nil)

        case .gitea, .custom:
            guard !account.host.isEmpty else { throw APIError.unsupportedHost }
            var request = try postRequest("https://\(account.host)/api/v1/user/repos")
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": name, "private": isPrivate, "auto_init": false,
            ])
            struct GTRepo: Decodable { let name: String; let full_name: String; let clone_url: String; let `private`: Bool }
            let r: GTRepo = try await sendJSON(request)
            return RemoteRepository(name: r.name, fullName: r.full_name, cloneURL: r.clone_url,
                                    description: nil, isPrivate: r.private, updatedAt: nil)
        }
    }

    private static func postRequest(_ urlString: String) throws -> URLRequest {
        guard let url = URL(string: urlString) else { throw APIError.unsupportedHost }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    // MARK: - HTTP

    private static func getJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.setValue("HelloNotes", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("No HTTP response.") }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw APIError.unauthorized
        default: throw APIError.http(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.transport("Unexpected response from the server.")
        }
    }

    /// POST + decode, with a friendlier message when the name already exists.
    private static func sendJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            return try await getJSON(request)
        } catch APIError.http(422), APIError.http(400), APIError.http(409) {
            throw APIError.transport("Couldn't create the repository — a repository with that name may already exist.")
        }
    }

    // MARK: - Dates

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFractional.date(from: string) ?? iso.date(from: string)
    }
}
