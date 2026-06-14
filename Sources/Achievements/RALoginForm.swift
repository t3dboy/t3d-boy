// T3d Boy — reusable RetroAchievements sign-in form.
//
// A self-contained NSView that shows either a username/password form (signed out)
// or an account summary with a Sign Out button (signed in). Used by both the
// onboarding "Achievements (optional)" step and the Preferences window, so the
// login flow lives in exactly one place.
//
// Security: the password is read straight from the secure field into
// rc_client_begin_login_with_password and never stored or logged — only the token
// rc_client returns is persisted, to the Keychain (see Achievements.persistToken…).

import Cocoa

final class RALoginForm: NSView {
    /// Called whenever the signed-in/out state changes, so hosts can refresh.
    var onChange: (() -> Void)?

    private let stack = NSStackView()
    private let usernameField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let signInButton = NSButton(title: "Sign In", target: nil, action: nil)
    private let createLink = NSButton(title: "Create an account…", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        usernameField.placeholderString = "RetroAchievements username"
        passwordField.placeholderString = "Password"
        for f in [usernameField, passwordField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 260).isActive = true
            f.target = self
            f.action = #selector(submit)
        }

        signInButton.bezelStyle = .rounded
        signInButton.keyEquivalent = "\r" // Return submits
        signInButton.target = self
        signInButton.action = #selector(submit)

        createLink.isBordered = false
        createLink.bezelStyle = .inline
        createLink.contentTintColor = .linkColor
        createLink.target = self
        createLink.action = #selector(openCreateAccount)
        createLink.font = theme.fontCaption

        status.font = theme.fontCaption
        status.textColor = theme.textSecondary
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 2
        status.preferredMaxLayoutWidth = 260

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Rebuild the stack for the current signed-in/out state.
    func refresh() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if Achievements.shared.isLoggedIn, let account = Achievements.shared.account {
            let who = NSTextField(labelWithString: "Signed in as \(account.username)")
            who.font = theme.skinned ? .rounded(13, .medium) : .systemFont(ofSize: 13, weight: .semibold)
            who.textColor = theme.textPrimary
            let pts = NSTextField(labelWithString: "\(account.points) points")
            pts.font = theme.fontCaption
            pts.textColor = theme.textSecondary
            let signOut = NSButton(title: "Sign Out", target: self, action: #selector(signOut))
            signOut.bezelStyle = .rounded
            stack.addArrangedSubview(who)
            stack.addArrangedSubview(pts)
            stack.addArrangedSubview(signOut)
        } else if !Achievements.shared.isAvailable {
            let msg = NSTextField(wrappingLabelWithString:
                "RetroAchievements is unavailable right now. The emulator works normally without it.")
            msg.font = theme.fontCaption
            msg.textColor = theme.textSecondary
            msg.preferredMaxLayoutWidth = 260
            stack.addArrangedSubview(msg)
        } else {
            let buttonRow = NSStackView(views: [signInButton, spinner])
            buttonRow.spacing = 8
            buttonRow.alignment = .centerY
            stack.addArrangedSubview(usernameField)
            stack.addArrangedSubview(passwordField)
            stack.addArrangedSubview(buttonRow)
            stack.addArrangedSubview(createLink)
            if !status.stringValue.isEmpty { stack.addArrangedSubview(status) }
            setControls(enabled: true)
        }
    }

    private func setControls(enabled: Bool) {
        usernameField.isEnabled = enabled
        passwordField.isEnabled = enabled
        signInButton.isEnabled = enabled
        if enabled { spinner.stopAnimation(nil) } else { spinner.startAnimation(nil) }
    }

    @objc private func submit() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordField.stringValue
        guard !username.isEmpty, !password.isEmpty else {
            showStatus("Enter your username and password.", error: true)
            return
        }
        showStatus("Signing in…", error: false)
        setControls(enabled: false)

        Achievements.shared.login(username: username, password: password) { [weak self] result in
            guard let self else { return }
            self.passwordField.stringValue = "" // never keep the password around
            switch result {
            case .success:
                self.status.stringValue = ""
                self.refresh()
                self.onChange?()
            case .failure(let error):
                self.setControls(enabled: true)
                self.showStatus(Self.message(for: error), error: true)
            }
        }
    }

    @objc private func signOut() {
        Achievements.shared.logout()
        refresh()
        onChange?()
    }

    @objc private func openCreateAccount() {
        if let url = URL(string: "https://retroachievements.org/createaccount.php") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showStatus(_ text: String, error: Bool) {
        status.stringValue = text
        status.textColor = error ? .systemRed : theme.textSecondary
        if status.superview == nil, !text.isEmpty { stack.addArrangedSubview(status) }
    }

    private static func message(for error: Error) -> String {
        if case RAError.server(let m) = error, !m.isEmpty { return m }
        return "Sign-in failed. Check your username and password and try again."
    }
}
