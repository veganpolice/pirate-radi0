import Foundation
import AuthenticationServices
import Security
import CryptoKit
import os

private let logger = Logger(subsystem: "com.pirateradio", category: "SpotifyAuth")

/// Manages Spotify OAuth/PKCE authentication with secure Keychain token storage.
@Observable
@MainActor
final class SpotifyAuthManager {
    // MARK: - Configuration

    /// Set these in your Spotify Developer Dashboard
    static let clientID = "441011e5cfc04417a7c9bc73fc295939"
    static let redirectURI = "pirate-radio://auth/callback" // TODO: Switch to Universal Link
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-private",
        "streaming",
    ].joined(separator: " ")

    // MARK: - State

    private(set) var isAuthenticated = false
    private(set) var isPremium = false
    private(set) var displayName: String?
    private(set) var userID: String?
    private(set) var error: PirateRadioError?

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var codeVerifier: String?

    // ASWebAuthenticationSession context provider
    private let webAuthContextProvider = WebAuthContextProvider()

    // MARK: - Init

    init() {
        loadTokensFromKeychain()
        if accessToken != nil {
            isAuthenticated = true
            Task { await refreshUserProfile() }
        }
    }

    // MARK: - Public API

    /// Start the Spotify OAuth/PKCE login flow using ASWebAuthenticationSession.
    func signIn() async {
        error = nil
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        guard let url = components.url else { return }
        logger.notice("Authorization URL: \(url.absoluteString)")
        logger.notice("Client ID: \(Self.clientID)")
        logger.notice("Redirect URI: \(Self.redirectURI)")

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: "pirate-radio"
                ) { callbackURL, error in
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: PirateRadioError.notAuthenticated)
                    }
                }
                session.presentationContextProvider = webAuthContextProvider
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }
            try await handleAuthCallback(callbackURL)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User cancelled — not an error
        } catch {
            self.error = .tokenRefreshFailed(underlying: error)
        }
    }

    /// Sign out and clear all tokens.
    func signOut() async {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        isPremium = false
        displayName = nil
        userID = nil
        deleteTokensFromKeychain()
    }

    /// Get a valid access token, refreshing if needed.
    func getAccessToken() async throws -> String {
        if let expiry = tokenExpiry, Date.now > expiry.addingTimeInterval(-120) {
            // Refresh proactively at 80% of expiry (2 min before)
            try await refreshAccessToken()
        }
        guard let token = accessToken else {
            throw PirateRadioError.tokenExpired
        }
        return token
    }

    // MARK: - OAuth Flow

    private func handleAuthCallback(_ url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            throw PirateRadioError.tokenExpired
        }

        // Exchange code for tokens
        let tokenResponse = try await exchangeCodeForTokens(code: code, verifier: verifier)
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        tokenExpiry = Date.now.addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        saveTokensToKeychain()
        codeVerifier = nil

        await refreshUserProfile()
        isAuthenticated = true
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": verifier,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func refreshAccessToken() async throws {
        guard let refreshToken else {
            throw PirateRadioError.tokenExpired
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        accessToken = response.accessToken
        tokenExpiry = Date.now.addingTimeInterval(TimeInterval(response.expiresIn))
        // Spotify may rotate the refresh token
        if let newRefresh = response.refreshToken {
            self.refreshToken = newRefresh
        }
        saveTokensToKeychain()
    }

    // MARK: - User Profile

    private func refreshUserProfile() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let profile = try? JSONDecoder().decode(SpotifyProfile.self, from: data) else {
            return
        }

        displayName = profile.displayName
        userID = profile.id
        isPremium = profile.product == "premium"

        if !isPremium {
            error = .spotifyNotPremium
        }
    }

    // MARK: - Demo Mode

    func enableDemoMode() {
        isAuthenticated = true
        isPremium = true
        displayName = "DJ Powder"
        userID = "demo-user-1"
    }

    // MARK: - PKCE

    /// Generate a cryptographically random code verifier (43-128 chars).
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    /// Generate SHA256 code challenge from verifier.
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded
    }

    // MARK: - Keychain

    private static let keychainService = "com.pirateradio.spotify"

    private func saveTokensToKeychain() {
        if let accessToken { KeychainHelper.save(key: "access_token", value: accessToken) }
        if let refreshToken { KeychainHelper.save(key: "refresh_token", value: refreshToken) }
        if let tokenExpiry {
            KeychainHelper.save(key: "token_expiry", value: String(tokenExpiry.timeIntervalSince1970))
        }
    }

    private func loadTokensFromKeychain() {
        accessToken = KeychainHelper.load(key: "access_token")
        refreshToken = KeychainHelper.load(key: "refresh_token")
        if let expiryStr = KeychainHelper.load(key: "token_expiry"),
           let expiry = TimeInterval(expiryStr) {
            tokenExpiry = Date(timeIntervalSince1970: expiry)
        }
    }

    private func deleteTokensFromKeychain() {
        KeychainHelper.delete(key: "access_token")
        KeychainHelper.delete(key: "refresh_token")
        KeychainHelper.delete(key: "token_expiry")
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    static let service = "com.pirateradio.spotify"

    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - API Models

private struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct SpotifyProfile: Codable {
    let id: String
    let displayName: String?
    let product: String? // "premium", "free", etc.

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case product
    }
}

// MARK: - ASWebAuthenticationSession Context

private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

// MARK: - Base64URL

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
