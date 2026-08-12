import Foundation
import OSLog

/// Skyward login: POST to skyporthttp.w and parse the caret-delimited token list.
enum SkywardAuthAPI {
    private static let logger = Logger(subsystem: "com.zacharywilson.elevate", category: "SkywardAuth")

    static func authenticate(credentials: SkywardCredentials) async throws -> SkywardSessionCodes {
        let base = credentials.baseURL.hasSuffix("/") ? credentials.baseURL : credentials.baseURL + "/"
        guard let loginPageURL = URL(string: base + "fwemnu01.w"),
              let authURL = URL(string: base + "skyporthttp.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }

        let loginPage = try await SkywardHTTP.get(url: loginPageURL, extraHeaders: [
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ])
        let body = try loginFields(from: loginPage, credentials: credentials)
        let origin = "\(authURL.scheme ?? "https")://\(authURL.host ?? "")"
        let response = try await SkywardHTTP.post(url: authURL, fields: body, extraHeaders: [
            "Accept": "*/*",
            "Origin": origin,
            "Referer": loginPageURL.absoluteString,
        ])
        let codes = try parseAuthResponse(response)
        storeLoginHistoryCookie(from: response, for: authURL)
        return codes
    }

    static func loginFields(
        from loginPage: String,
        credentials: SkywardCredentials
    ) throws -> [(String, String)] {
        let root = MiniHTML.parse(loginPage)
        guard let form = root.querySelector("form#detailform") else {
            throw SkywardError.invalidResponse("login form not found")
        }

        let overrides = [
            "login": credentials.username,
            "password": credentials.password,
            "Browser": "Safari",
            "BrowserVersion": "17",
            "BrowserPlatform": "iPhone",
            "TouchDevice": "true",
            "screenWidth": "393",
            "screenHeight": "852",
            "userAgent": SkywardHTTP.userAgent,
            "osName": "Apple iPhone iOS 17",
            "brwsInfo": "Safari Mobile 17",
            "subversion": "17",
            "supported": "true",
        ]
        var fields: [(String, String)] = [
            ("requestAction", "eel"),
            ("method", "extrainfo"),
            ("codeType", "tryLogin"),
            ("codeValue", credentials.username),
        ]

        for input in form.querySelectorAll("input") {
            guard let name = input.attribute("name"), !name.isEmpty else { continue }
            let type = (input.attribute("type") ?? "text").lowercased()
            let value: String
            if type == "checkbox" {
                value = input.attributes["checked"] == nil ? "off" : "on"
            } else if let override = overrides[name] {
                value = override
            } else {
                value = HTMLEntities.decode(input.attribute("value") ?? "")
            }
            if !value.isEmpty { fields.append((name, value)) }
        }

        fields.append(("cUserRole", "family/student"))
        fields.append(("fwtimestamp", String(Int(Date().timeIntervalSince1970 * 1_000))))

        let fieldNames = Set(fields.map(\.0))
        guard fieldNames.contains("hAnon"), fieldNames.contains("hIPInfo") else {
            throw SkywardError.invalidResponse("login page missing required session state")
        }
        #if DEBUG
        logger.debug("Prepared browser-compatible login fields count=\(fields.count, privacy: .public) hasAnon=\(fieldNames.contains("hAnon"), privacy: .public) hasIP=\(fieldNames.contains("hIPInfo"), privacy: .public)")
        #endif
        return fields
    }

    private static func storeLoginHistoryCookie(from response: String, for url: URL) {
        let response = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.hasPrefix("<li>"), response.hasSuffix("</li>"),
              let host = url.host else { return }
        let tokens = response.dropFirst(4).dropLast(5).split(separator: "^", omittingEmptySubsequences: false)
        var offset = 0
        while offset < tokens.count && tokens[offset].isEmpty { offset += 1 }
        guard tokens.indices.contains(offset + 16),
              !tokens[offset + 15].isEmpty, !tokens[offset + 16].isEmpty,
              let cookie = HTTPCookie(properties: [
                .domain: host,
                .path: "/",
                .name: String(tokens[offset + 15]),
                .value: String(tokens[offset + 16]),
                .secure: "TRUE",
              ]) else { return }
        SkywardHTTP.session.configuration.httpCookieStorage?.setCookie(cookie)
    }

    static func parseAuthResponse(_ postResponse: String) throws -> SkywardSessionCodes {
        let response = postResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        let caretCount = response.reduce(into: 0) { count, character in
            if character == "^" { count += 1 }
        }
        logger.debug(
            "Parsing auth response characters=\(response.count, privacy: .public) utf8Bytes=\(response.utf8.count, privacy: .public) carets=\(caretCount, privacy: .public) hasListWrapper=\(response.hasPrefix("<li>") && response.hasSuffix("</li>"), privacy: .public)"
        )
        #endif

        guard response.count > 9 else {
            #if DEBUG
            logger.error("Auth response too short characters=\(response.count, privacy: .public)")
            #endif
            throw SkywardError.invalidResponse("login response too short")
        }
        let plain = MiniHTML.parse(response).text.lowercased()
        if plain.contains("invalid username or password")
            || plain.contains("invalid user")
            || plain.contains("invalid login") {
            throw SkywardError.invalidCredentials
        }
        guard response.hasPrefix("<li>"), response.hasSuffix("</li>") else {
            throw SkywardError.invalidResponse("authentication response had unexpected format")
        }

        let dissected = String(response.dropFirst(4).dropLast(5))
        let toks = dissected.components(separatedBy: "^")

        // Some districts return leading empty tokens, shifting all indices.
        var offset = 0
        while offset < toks.count && toks[offset].isEmpty { offset += 1 }
        guard toks.count >= offset + 15 else {
            #if DEBUG
            logger.error("Auth token parsing failed tokens=\(toks.count, privacy: .public) offset=\(offset, privacy: .public)")
            #endif
            throw SkywardError.invalidResponse("authentication response had too few fields")
        }

        let dwd = toks[offset]
        let wfaacl = toks[offset + 3]
        let userType = toks[offset + 6]
        let encses = toks[offset + 14]
        let sessionid = "\(toks[offset + 1])\u{15}\(toks[offset + 2])"

        guard !dwd.isEmpty, !wfaacl.isEmpty, !encses.isEmpty else {
            #if DEBUG
            logger.error(
                "Auth response missing session codes tokens=\(toks.count, privacy: .public) offset=\(offset, privacy: .public) hasDwd=\(!dwd.isEmpty, privacy: .public) hasWfaacl=\(!wfaacl.isEmpty, privacy: .public) hasEncses=\(!encses.isEmpty, privacy: .public)"
            )
            #endif
            throw SkywardError.invalidResponse("missing essential session codes")
        }
        #if DEBUG
        logger.debug("Auth response parsed successfully tokens=\(toks.count, privacy: .public) offset=\(offset, privacy: .public)")
        #endif
        return SkywardSessionCodes(dwd: dwd, wfaacl: wfaacl, encses: encses, userType: userType, sessionid: sessionid)
    }
}
